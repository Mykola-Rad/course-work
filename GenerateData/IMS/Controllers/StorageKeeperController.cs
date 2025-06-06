﻿using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using IMS.Data;
using IMS.ViewModels;
using IMS.Models;
using X.PagedList.EF;
using X.PagedList;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireManagerRole")]
    [Route("StorageKeepers")]
    public class StorageKeeperController : Controller
    {
        private readonly AppDbContext _context;
        private readonly ILogger<StorageKeeperController> _logger;
        private const int _pageSize = 10;

        public StorageKeeperController(AppDbContext context, ILogger<StorageKeeperController> logger)
        {
            _context = context;
            _logger = logger;
        }

        // GET: StorageKeepers/Index 
        [HttpGet("")]
        public async Task<IActionResult> Index(
        string? filterFullName = null,
        string? filterPhone = null,
        string? filterEmail = null,
        string? filterStorageName = null,
        int page = 1)
        {
            ViewData["Title"] = "Керування комірниками";

            ViewData["CurrentFullNameFilter"] = filterFullName; 
            ViewData["CurrentPhoneFilter"] = filterPhone;
            ViewData["CurrentEmailFilter"] = filterEmail;
            ViewData["CurrentStorageFilter"] = filterStorageName;

            int pageNumber = page;

            try
            {
                var keepersQuery = _context.StorageKeepers
                                           .Include(sk => sk.StorageNameNavigation)
                                           .AsNoTracking() 
                                           .AsQueryable();

                if (!string.IsNullOrEmpty(filterFullName))
                {
                    string searchTerm = filterFullName.Trim();
                    keepersQuery = keepersQuery.Where(sk =>
                        EF.Functions.ToTsVector("simple", (sk.FirstName ?? "") + " " + (sk.LastName ?? ""))
                        .Matches(EF.Functions.PlainToTsQuery("simple", searchTerm))
                    );
                }

                if (!string.IsNullOrEmpty(filterPhone))
                {
                    keepersQuery = keepersQuery.Where(sk => sk.PhoneNumber.StartsWith(filterPhone));
                }
                if (!string.IsNullOrEmpty(filterEmail))
                {
                    keepersQuery = keepersQuery.Where(sk => sk.Email != null && sk.Email.ToLower().Contains(filterEmail.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterStorageName))
                {
                    keepersQuery = keepersQuery.Where(sk => sk.StorageName == filterStorageName);
                }

                await PopulateStorageFilterList(filterStorageName);

                var sortedQuery = keepersQuery.OrderBy(sk => sk.LastName).ThenBy(sk => sk.FirstName);

                var pagedStorageKeepers = await sortedQuery.ToPagedListAsync(pageNumber, _pageSize);

                return View(pagedStorageKeepers); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку комірників з фільтрами");
                TempData["ErrorMessage"] = "Не вдалося завантажити список комірників.";
                await PopulateStorageFilterList(filterStorageName);
                var emptyPagedList = new PagedList<StorageKeeper>(Enumerable.Empty<StorageKeeper>(), pageNumber, _pageSize);
                return View(emptyPagedList);
            }
        }

        private async Task PopulateStorageFilterList(string? selectedStorageName)
        {
            try
            {
                var storageList = await _context.Storages.OrderBy(s => s.Name).Select(s => s.Name).ToListAsync();
                ViewBag.StorageFilterList = new SelectList(storageList, selectedStorageName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to populate Storage filter list.");
                ViewBag.StorageFilterList = new SelectList(new List<string>()); 
            }
        }

        [HttpGet("AutocompleteFullName")]
        public async Task<IActionResult> AutocompleteFullName(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2)
            {
                return Json(Enumerable.Empty<string>());
            }
            var searchTerm = term.Trim();
            try
            {
                var query = _context.StorageKeepers
                    .Where(sk =>
                        EF.Functions.ToTsVector("simple", (sk.FirstName ?? "") + " " + (sk.LastName ?? ""))
                        .Matches(EF.Functions.PlainToTsQuery("simple", searchTerm))
                    )

                    .Select(sk => (sk.FirstName ?? "") + " " + (sk.LastName ?? ""))
                    .Where(fullName => !string.IsNullOrWhiteSpace(fullName))
                    .Distinct()
                    .OrderBy(fullName => fullName)
                    .Take(10);

                var matches = await query.ToListAsync();

                return Json(matches);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during storage keeper FTS (on-the-fly) autocomplete for term {Term}", term);
                return Json(Enumerable.Empty<string>());
            }
        }


        // GET: StorageKeepers/Create
        // GET: StorageKeepers/Create?storageName=НазваСкладу
        [HttpGet("Create")]
        public async Task<IActionResult> Create(string? storageName = null)
        {
            ViewData["Title"] = "Додати нового комірника";
            var viewModel = new StorageKeeperViewModel();

            if (!string.IsNullOrEmpty(storageName))
            {
                if (await _context.Storages.AnyAsync(s => s.Name == storageName))
                {
                    viewModel.StorageName = storageName;
                    ViewData["Title"] = $"Додати комірника на склад '{storageName}'";
                    ViewBag.ContextStorageName = storageName;
                }
                else
                {
                    _logger.LogWarning("Attempted to pre-select non-existent storage '{StorageName}' for new keeper.", storageName);
                }
            }

            await PopulateStoragesDropDownList(viewModel);
            return View(viewModel);
        }

        // POST: StorageKeepers/Create
        [HttpPost("Create")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(StorageKeeperViewModel model, string? contextStorageName)
        {
            if (await StorageKeeperExists(model.PhoneNumber))
            {
                ModelState.AddModelError("PhoneNumber", $"Комірник з номером телефону '{model.PhoneNumber}' вже існує.");
            }
            if (!await _context.Storages.AnyAsync(s => s.Name == model.StorageName))
            {
                ModelState.AddModelError("StorageName", "Обраний склад не існує.");
            }

            ModelState.Remove(nameof(model.OriginalPhoneNumber));
            ModelState.Remove(nameof(model.IsEditMode));
            ModelState.Remove("User");
            ModelState.Remove("StorageNameNavigation");

            if (ModelState.IsValid)
            {
                var storageKeeper = new StorageKeeper
                {
                    PhoneNumber = model.PhoneNumber,
                    FirstName = model.FirstName,
                    LastName = model.LastName,
                    Email = model.Email,
                    StorageName = model.StorageName,
                    UserId = null
                };

                try
                {
                    _context.StorageKeepers.Add(storageKeeper);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Профіль комірника '{storageKeeper.FirstName} {storageKeeper.LastName}' успішно створено.";

                    if (!string.IsNullOrEmpty(contextStorageName))
                    {
                        return RedirectToAction("Details", "Storage", new { name = model.StorageName });
                    }

                    return RedirectToAction(nameof(Index));
                }
                catch (DbUpdateException ex)
                {
                    _logger.LogError(ex, "Помилка БД при створенні комірника {PhoneNumber}", model.PhoneNumber);
                    if (ex.InnerException is Npgsql.PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation)
                    {
                        if (pgEx.ConstraintName != null && pgEx.ConstraintName.Contains("email"))
                        {
                            ModelState.AddModelError("Email", "Такий Email вже використовується.");
                        }
                        else
                        {
                            ModelState.AddModelError("PhoneNumber", "Такий номер телефону вже існує (конфлікт БД).");
                        }
                    }
                    else
                    {
                        ModelState.AddModelError("", "Не вдалося створити профіль комірника. Помилка бази даних.");
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Загальна помилка при створенні комірника {PhoneNumber}", model.PhoneNumber);
                    ModelState.AddModelError("", "Не вдалося створити профіль комірника.");
                }
            }

            await PopulateStoragesDropDownList(model);
            ViewData["Title"] = "Створити нового комірника (Помилка)";
            return View(model);
        }

        // GET: StorageKeepers/Edit/0991234567
        [HttpGet("Edit/{phoneNumber}")]
        public async Task<IActionResult> Edit(string phoneNumber)
        {
            if (string.IsNullOrEmpty(phoneNumber)) return BadRequest();

            var storageKeeper = await _context.StorageKeepers.FindAsync(phoneNumber);
            if (storageKeeper == null)
            {
                _logger.LogWarning("Спроба редагування неіснуючого комірника: {PhoneNumber}", phoneNumber);
                TempData["ErrorMessage"] = $"Профіль комірника з номером '{phoneNumber}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            // Готуємо ViewModel
            var viewModel = new StorageKeeperViewModel
            {
                OriginalPhoneNumber = storageKeeper.PhoneNumber,
                PhoneNumber = storageKeeper.PhoneNumber,
                FirstName = storageKeeper.FirstName,
                LastName = storageKeeper.LastName,
                Email = storageKeeper.Email,
                StorageName = storageKeeper.StorageName
            };

            await PopulateStoragesDropDownList(viewModel);

            ViewData["Title"] = $"Редагувати комірника: {viewModel.FirstName} {viewModel.LastName}";
            return View(viewModel);
        }

        // POST: StorageKeepers/Edit/СтарийНомерТелефону
        [HttpPost("Edit/{originalPhoneNumber}")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit([FromRoute] string originalPhoneNumber, StorageKeeperViewModel model)
        {
            if (string.IsNullOrEmpty(originalPhoneNumber)) return BadRequest("Original phone number not provided.");
            if (model == null) return BadRequest("Form data missing.");
            model.OriginalPhoneNumber = originalPhoneNumber;

            if (originalPhoneNumber != model.PhoneNumber && await StorageKeeperExists(model.PhoneNumber))
            {
                ModelState.AddModelError("PhoneNumber", $"Комірник з номером телефону '{model.PhoneNumber}' вже існує.");
            }
            if (!await _context.Storages.AnyAsync(s => s.Name == model.StorageName))
            {
                ModelState.AddModelError("StorageName", "Обраний склад не існує.");
            }
            if (!string.IsNullOrEmpty(model.Email))
            {
                var existingKeeper = await _context.StorageKeepers.AsNoTracking().FirstOrDefaultAsync(k => k.PhoneNumber == originalPhoneNumber);
                if (existingKeeper != null && existingKeeper.Email != model.Email)
                {
                    if (await _context.StorageKeepers.AnyAsync(k => k.Email == model.Email && k.PhoneNumber != originalPhoneNumber))
                    {
                        ModelState.AddModelError("Email", "Такий Email вже використовується іншим комірником.");
                    }
                }
            }

            ModelState.Remove(nameof(model.IsEditMode));
            ModelState.Remove(nameof(model.AvailableStorages));

            if (ModelState.IsValid)
            {
                string sql = @"UPDATE public.storage_keeper
                        SET phone_number = {0}, first_name = {1}, last_name = {2}, email = {3}, storage_name = {4}
                        WHERE phone_number = {5}";
                try
                {
                    int affectedRows = await _context.Database.ExecuteSqlRawAsync(sql,
                        model.PhoneNumber,
                        model.FirstName,
                        model.LastName,
                        model.Email,
                        model.StorageName,
                        originalPhoneNumber
                    );

                    if (affectedRows > 0)
                    {
                        TempData["SuccessMessage"] = $"Профіль комірника '{model.FirstName} {model.LastName}' успішно оновлено.";
                        return RedirectToAction(nameof(Index));
                    }
                    else
                    {
                        _logger.LogWarning("Спроба оновлення неіснуючого комірника (ориг. тел {OriginalPhoneNumber})", originalPhoneNumber);
                        TempData["ErrorMessage"] = "Профіль комірника, який ви намагаєтесь редагувати, не знайдено.";
                        return RedirectToAction(nameof(Index));
                    }
                }
                catch (DbUpdateException ex)
                {
                    _logger.LogError(ex, "Помилка БД при оновленні комірника (ориг. тел {OriginalPhoneNumber}) через Raw SQL", originalPhoneNumber);
                    if (ex.InnerException is Npgsql.PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation)
                    {
                        if (pgEx.ConstraintName != null && pgEx.ConstraintName.Contains("phone_number"))
                        {
                            ModelState.AddModelError("PhoneNumber", "Такий номер телефону вже існує (конфлікт БД).");
                        }
                        else if (pgEx.ConstraintName != null && pgEx.ConstraintName.Contains("email"))
                        {
                            ModelState.AddModelError("Email", "Такий Email вже використовується (конфлікт БД).");
                        }
                        else
                        {
                            ModelState.AddModelError("", "Помилка збереження даних. Можливо, порушено унікальність запису.");
                        }
                    }
                    else
                    {
                        ModelState.AddModelError("", "Не вдалося оновити профіль комірника. Помилка бази даних.");
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Загальна помилка при оновленні комірника (ориг. тел {OriginalPhoneNumber}) через Raw SQL", originalPhoneNumber);
                    ModelState.AddModelError("", "Не вдалося оновити профіль комірника.");
                }
            }

            await PopulateStoragesDropDownList(model);
            ViewData["Title"] = $"Редагувати: {model.FirstName} {model.LastName} (Помилка)";
            return View(model);
        }

        // GET: StorageKeepers/Delete/0991234567
        [HttpGet("Delete/{phoneNumber}")]
        public async Task<IActionResult> Delete(string phoneNumber)
        {
            if (string.IsNullOrEmpty(phoneNumber)) return NotFound();

            ViewData["Title"] = $"Видалити комірника: {phoneNumber}";

            var storageKeeper = await _context.StorageKeepers
                                            .Include(sk => sk.User)
                                            .Include(sk => sk.StorageNameNavigation)
                                            .FirstOrDefaultAsync(m => m.PhoneNumber == phoneNumber);

            if (storageKeeper == null)
            {
                _logger.LogWarning("Спроба видалення неіснуючого комірника: {PhoneNumber}", phoneNumber);
                TempData["ErrorMessage"] = $"Профіль комірника з номером '{phoneNumber}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            bool hasUserLink = storageKeeper.UserId != null;
            bool hasInvoices = await _context.Invoices.AnyAsync(i => i.SenderKeeperPhone == phoneNumber || i.ReceiverKeeperPhone == phoneNumber);

            ViewBag.CanDelete = !(hasUserLink || hasInvoices);
            string warnings = "";
            if (hasUserLink) warnings += $"До профілю прив'язаний користувач ('{storageKeeper.User?.Username}'). Спочатку видаліть користувача. ";
            if (hasInvoices) warnings += "Комірник фігурує в накладних. ";
            ViewBag.WarningMessage = string.IsNullOrEmpty(warnings) ? null : $"Неможливо видалити: {warnings.Trim()}";

            return View(storageKeeper);
        }

        // POST: StorageKeepers/Delete/0991234567
        [HttpPost("Delete/{phoneNumber}"), ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(string phoneNumber)
        {
            if (string.IsNullOrEmpty(phoneNumber)) return NotFound();

            var storageKeeper = await _context.StorageKeepers.FindAsync(phoneNumber);
            if (storageKeeper == null)
            {
                TempData["ErrorMessage"] = $"Профіль комірника '{phoneNumber}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            bool hasUserLink = storageKeeper.UserId != null;
            bool hasInvoices = await _context.Invoices.AnyAsync(i => i.SenderKeeperPhone == phoneNumber || i.ReceiverKeeperPhone == phoneNumber);

            if (hasUserLink || hasInvoices)
            {
                _logger.LogWarning("Спроба видалення комірника '{PhoneNumber}', що має залежності.", phoneNumber);
                string errorMsg = "Неможливо видалити профіль комірника, оскільки ";
                if (hasUserLink) errorMsg += "до нього прив'язаний користувач; ";
                if (hasInvoices) errorMsg += "він фігурує в накладних; ";
                TempData["ErrorMessage"] = errorMsg.Trim();
                return RedirectToAction(nameof(Index));
            }

            try
            {
                _context.StorageKeepers.Remove(storageKeeper);
                await _context.SaveChangesAsync();
                TempData["SuccessMessage"] = $"Профіль комірника '{storageKeeper.FirstName} {storageKeeper.LastName}' ({phoneNumber}) успішно видалено.";
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при видаленні комірника {PhoneNumber}", phoneNumber);
                TempData["ErrorMessage"] = "Не вдалося видалити профіль комірника.";
            }

            return RedirectToAction(nameof(Index));
        }

        // GET: StorageKeepers/Details/0991234567
        // GET: StorageKeepers/Details/0991234567?fromStorage=true
        [HttpGet("Details/{phoneNumber}")]
        public async Task<IActionResult> Details(
        string phoneNumber,
        [FromQuery] bool fromStorage = false, 
        string activeTab = "info",           
        int iPage = 1                         
        )
        {
            if (string.IsNullOrEmpty(phoneNumber)) return BadRequest();

            ViewData["ActiveTab"] = activeTab; 
            try
            {
                var storageKeeper = await _context.StorageKeepers
                    .Include(sk => sk.StorageNameNavigation)
                    .Include(sk => sk.User)
                    .AsNoTracking()
                    .FirstOrDefaultAsync(sk => sk.PhoneNumber == phoneNumber);

                if (storageKeeper == null)
                {
                    TempData["ErrorMessage"] = $"Профіль комірника '{phoneNumber}' не знайдено.";
                    if (fromStorage && !string.IsNullOrEmpty(storageKeeper?.StorageName))
                    {
                        return RedirectToAction(nameof(Index));
                    }
                    return RedirectToAction(nameof(Index));
                }

                if (fromStorage)
                {
                    ViewData["Title"] = $"Деталі: {storageKeeper.FirstName} {storageKeeper.LastName} (зі складу {storageKeeper.StorageName})";
                }
                else
                {
                    ViewData["Title"] = $"Деталі: {storageKeeper.FirstName} {storageKeeper.LastName} ({phoneNumber})";
                }

                IPagedList<Invoice>? pagedInvoices = null; 
                if (!fromStorage || activeTab == "invoices")
                {
                    var invoicesQuery = _context.Invoices
                       .Where(i => i.SenderKeeperPhone == phoneNumber || i.ReceiverKeeperPhone == phoneNumber)
                       .Include(i => i.ListEntries)
                       .OrderByDescending(i => i.Date).ThenByDescending(i => i.InvoiceId)
                       .AsNoTracking();
                    pagedInvoices = await invoicesQuery.ToPagedListAsync(iPage, _pageSize);
                }
                else
                {
                    pagedInvoices = new PagedList<Invoice>(Enumerable.Empty<Invoice>(), iPage, _pageSize);
                }

                var viewModel = new StorageKeeperDetailsViewModel
                {
                    Keeper = storageKeeper,
                    RelatedInvoices = pagedInvoices, 
                    CurrentInvoicesPage = iPage,      
                    FromStorage = fromStorage      
                };

                return View(viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей комірника {PhoneNumber}", phoneNumber);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталі комірника.";
                return RedirectToAction(nameof(Index));
            }
        }

        private async Task<bool> StorageKeeperExists(string phoneNumber)
        {
            return await _context.StorageKeepers.AnyAsync(e => e.PhoneNumber == phoneNumber);
        }

        private async Task PopulateStoragesDropDownList(StorageKeeperViewModel model)
        {
            var storagesQuery = _context.Storages.OrderBy(s => s.Name);

            var storageList = await storagesQuery
                .Select(s => new SelectListItem { Value = s.Name, Text = s.Name })
                .ToListAsync();
            model.AvailableStorages = new SelectList(storageList, "Value", "Text", model.StorageName);
        }
    }
}
