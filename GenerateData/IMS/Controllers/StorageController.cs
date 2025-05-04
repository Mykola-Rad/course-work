using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data; 
using IMS.Models;
using Npgsql;
using IMS.ViewModels;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireStorageKeeperRole")]
    public class StorageController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<StorageController> _logger;

        public StorageController(AppDbContext context, ILogger<StorageController> logger)
        {
            _context = context;
            _logger = logger;
        }

        // GET: Storage
        public async Task<IActionResult> Index()
        {
            ViewData["Title"] = "Довідник складів";
            try
            {
                var storages = await _context.Storages
                                            .OrderBy(s => s.Name)
                                            .ToListAsync();
                return View(storages);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку складів");
                TempData["ErrorMessage"] = "Не вдалося завантажити список складів.";
                return View(new List<Storage>());
            }
        }

        // GET: Storage/Details/НазваСкладу
        [HttpGet("Details/{name}")]
        [Authorize(Policy = "RequireStorageKeeperRole")]
        public async Task<IActionResult> Details(string name)
        {
            if (string.IsNullOrEmpty(name)) return BadRequest();

            ViewData["Title"] = $"Деталі складу: {name}";

            try
            {
                var storage = await _context.Storages
                                            .AsNoTracking()
                                            .FirstOrDefaultAsync(m => m.Name == name);

                if (storage == null)
                {
                    _logger.LogWarning("Спроба перегляду деталей неіснуючого складу: {StorageName}", name);
                    TempData["ErrorMessage"] = $"Склад з назвою '{name}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                var viewModel = new StorageDetailsViewModel
                {
                    Storage = storage,
                    RelatedInvoices = new List<Invoice>(),
                };


                viewModel.Storage.StorageProducts = await _context.StorageProducts
                        .Where(sp => sp.StorageName == name)
                        .Include(sp => sp.ProductNameNavigation)
                            .ThenInclude(p => p.UnitCodeNavigation)
                        .OrderBy(sp => sp.ProductName)
                        .AsNoTracking()
                        .ToListAsync();

                viewModel.Storage.StorageKeepers = await _context.StorageKeepers
                        .Where(sk => sk.StorageName == name)
                        .Include(sk => sk.User)
                        .OrderBy(sk => sk.LastName).ThenBy(sk => sk.FirstName)
                        .AsNoTracking()
                        .ToListAsync();

                var senderInvoices = await _context.Invoices
                                           .Where(i => i.SenderStorageName == name)
                                           .Include(i => i.ListEntries)
                                           .AsNoTracking()
                                           .ToListAsync();
                var receiverInvoices = await _context.Invoices
                                            .Where(i => i.ReceiverStorageName == name)
                                            .Include(i => i.ListEntries)
                                            .AsNoTracking()
                                            .ToListAsync();

                viewModel.RelatedInvoices = senderInvoices
                                          .Union(receiverInvoices)
                                          .DistinctBy(i => i.InvoiceId)
                                          .OrderByDescending(i => i.Date)
                                          .ThenByDescending(i => i.InvoiceId)
                                          .ToList();


                return View(viewModel); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей складу {StorageName}", name);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталі складу.";
                return RedirectToAction(nameof(Index));
            }
        }

        [Authorize(Policy = "RequireManagerRole")]
        public IActionResult Create()
        {
            ViewData["Title"] = "Створити новий склад";
            return View();
        }

        // POST: Storage/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Create([Bind("Name,StreetName,HouseNumber,City,Region,PostalCode")] Storage storage)
        {
            if (await StorageExists(storage.Name))
            {
                ModelState.AddModelError("Name", $"Склад з назвою '{storage.Name}' вже існує.");
            }

            if (ModelState.IsValid)
            {
                try
                {
                    _context.Storages.Add(storage);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Склад '{storage.Name}' успішно створено.";
                    return RedirectToAction(nameof(Index));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при створенні складу {StorageName}", storage.Name);
                    ModelState.AddModelError("", "Не вдалося створити склад. Спробуйте ще раз.");
                }
            }
            ViewData["Title"] = "Створити новий склад (Помилка)";
            return View(storage);
        }

        // GET: Storage/Edit/НазваСкладу
        [HttpGet("Storage/Edit/{name}")]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Edit(string name)
        {
            if (string.IsNullOrEmpty(name)) return BadRequest();

            var storage = await _context.Storages.FindAsync(name);
            if (storage == null) return NotFound();

            ViewData["Title"] = $"Редагувати склад: {name}";
            ViewBag.OriginalName = name;
            return View(storage);
        }

        // POST: Storage/Edit/СтараНазваСкладу
        [HttpPost("Storage/Edit/{originalName}")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Edit([FromRoute] string originalName, [Bind("Name,StreetName,HouseNumber,City,Region,PostalCode")] Storage storageFromForm)
        {
            if (string.IsNullOrEmpty(originalName)) return BadRequest("Original storage name not provided.");
            if (storageFromForm == null) return BadRequest("Form data missing.");

            if (originalName != storageFromForm.Name && await StorageExists(storageFromForm.Name))
            {
                ModelState.AddModelError("Name", $"Склад з назвою '{storageFromForm.Name}' вже існує.");
            }

            if (ModelState.IsValid)
            {
                string sql = @"UPDATE public.storage
                        SET name = {0}, street_name = {1}, house_number = {2}, city = {3}, region = {4}, postal_code = {5}
                        WHERE name = {6}";
                try
                {
                    int affectedRows = await _context.Database.ExecuteSqlRawAsync(sql,
                        storageFromForm.Name,       
                        storageFromForm.StreetName,  
                        storageFromForm.HouseNumber, 
                        storageFromForm.City,        
                        storageFromForm.Region,      
                        storageFromForm.PostalCode,  
                        originalName                 
                    );

                    if (affectedRows > 0)
                    {
                        TempData["SuccessMessage"] = $"Склад '{storageFromForm.Name}' успішно оновлено.";
                        return RedirectToAction(nameof(Index));
                    }
                    else
                    {
                        _logger.LogWarning("Спроба оновлення неіснуючого складу (ориг. назва {OriginalStorageName})", originalName);
                        TempData["ErrorMessage"] = "Склад, який ви намагаєтесь редагувати, не знайдено.";
                        return RedirectToAction(nameof(Index));
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при оновленні складу (ориг. назва {OriginalStorageName}) через Raw SQL", originalName);
                    ModelState.AddModelError("", "Не вдалося оновити склад.");
                    if (ex.InnerException is PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation)
                    {
                        ModelState.AddModelError("Name", "Склад з такою новою назвою вже існує (конфлікт БД).");
                    }
                }
            }

            ViewData["Title"] = $"Редагувати склад: {originalName} (Помилка)";
            ViewBag.OriginalName = originalName; 
            return View(storageFromForm); 
        }


        // GET: Storage/Delete/НазваСкладу
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Delete(string name)
        {
            if (string.IsNullOrEmpty(name)) return NotFound();

            ViewData["Title"] = $"Видалити склад: {name}";
            var storage = await _context.Storages.FindAsync(name);
            if (storage == null) return NotFound();

            bool hasStock = await _context.StorageProducts.AnyAsync(sp => sp.StorageName == name);
            bool hasInvoices = await _context.Invoices.AnyAsync(i => i.SenderStorageName == name || i.ReceiverStorageName == name);
            bool hasKeepers = await _context.StorageKeepers.AnyAsync(sk => sk.StorageName == name);

            ViewBag.CanDelete = !(hasStock || hasInvoices || hasKeepers);
            string warnings = "";
            if (hasStock) warnings += "На складі є залишки товарів. ";
            if (hasInvoices) warnings += "Склад фігурує в накладних. ";
            if (hasKeepers) warnings += "До складу прив'язані комірники. ";
            ViewBag.WarningMessage = string.IsNullOrEmpty(warnings) ? null : $"Неможливо видалити: {warnings.Trim()}";

            return View(storage);
        }

        // POST: Storage/Delete/НазваСкладу
        [HttpPost, ActionName("Delete")] 
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> DeleteConfirmed(string name)
        {
            if (string.IsNullOrEmpty(name)) return NotFound();

            try
            {
                bool hasStock = await _context.StorageProducts.AnyAsync(sp => sp.StorageName == name);
                bool hasInvoices = await _context.Invoices.AnyAsync(i => i.SenderStorageName == name || i.ReceiverStorageName == name);
                bool hasKeepers = await _context.StorageKeepers.AnyAsync(sk => sk.StorageName == name);

                if (hasStock || hasInvoices || hasKeepers)
                {
                    _logger.LogWarning("Спроба видалення складу '{StorageName}', що має залежності.", name);
                    string errorMsg = "Неможливо видалити склад, оскільки ";
                    if (hasStock) errorMsg += "на ньому є залишки товарів; ";
                    if (hasInvoices) errorMsg += "він фігурує в накладних; ";
                    if (hasKeepers) errorMsg += "до нього прив'язані комірники; ";
                    TempData["ErrorMessage"] = errorMsg.Trim();
                    return RedirectToAction(nameof(Index));
                }

                var storage = await _context.Storages.FindAsync(name);
                if (storage != null)
                {
                    _context.Storages.Remove(storage);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Склад '{name}' успішно видалено.";
                }
                else
                {
                    TempData["ErrorMessage"] = $"Склад '{name}' не знайдено.";
                }
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при видаленні складу {StorageName}", name);
                TempData["ErrorMessage"] = "Не вдалося видалити склад.";
                return RedirectToAction(nameof(Index));
            }
        }

        private async Task<bool> StorageExists(string name)
        {
            return await _context.Storages.AnyAsync(e => e.Name == name);
        }

    }
}