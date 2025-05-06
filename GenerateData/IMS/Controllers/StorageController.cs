using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data; 
using IMS.Models;
using Npgsql;
using IMS.ViewModels;
using X.PagedList.EF;
using X.PagedList;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireStorageKeeperRole")]
    public class StorageController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<StorageController> _logger;
        private const int _pageSize = 10;

        public StorageController(AppDbContext context, ILogger<StorageController> logger)
        {
            _context = context;
            _logger = logger;
        }

        // GET: Storage
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Index(
        string? filterName = null,
        string? filterCity = null,
        string? filterStreet = null,
        string? filterRegion = null,
        int page = 1)
        {
            ViewData["Title"] = "Довідник складів";

            ViewData["CurrentNameFilter"] = filterName;
            ViewData["CurrentCityFilter"] = filterCity;
            ViewData["CurrentStreetFilter"] = filterStreet;
            ViewData["CurrentRegionFilter"] = filterRegion;

            int pageNumber = page;

            try
            {
                var storagesQuery = _context.Storages
                                            .AsNoTracking() 
                                            .AsQueryable();

                if (!string.IsNullOrEmpty(filterName))
                {
                    storagesQuery = storagesQuery.Where(s => s.Name.ToLower().Contains(filterName.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterCity))
                {
                    storagesQuery = storagesQuery.Where(s => s.City.ToLower().Contains(filterCity.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterStreet))
                {
                    storagesQuery = storagesQuery.Where(s => s.StreetName != null && s.StreetName.ToLower().Contains(filterStreet.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterRegion))
                {
                    storagesQuery = storagesQuery.Where(s => s.Region == filterRegion);
                }

                await PopulateFilterLists(filterRegion);

                var sortedQuery = storagesQuery.OrderBy(s => s.Name);

                var pagedStorages = await sortedQuery.ToPagedListAsync(pageNumber, _pageSize);

                return View(pagedStorages); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку складів з фільтрами");
                TempData["ErrorMessage"] = "Не вдалося завантажити список складів.";
                await PopulateFilterLists(filterRegion);
                var emptyPagedList = new PagedList<Storage>(Enumerable.Empty<Storage>(), pageNumber, _pageSize);
                return View(emptyPagedList);
            }
        }

        private async Task PopulateFilterLists(string? selectedRegion)
        {
            try
            {
                var regions = await _context.Storages
                                       .Where(s => !string.IsNullOrEmpty(s.Region)) 
                                       .Select(s => s.Region) 
                                       .Distinct()            
                                       .OrderBy(r => r)       
                                       .ToListAsync();
                ViewBag.RegionFilterList = new SelectList(regions, selectedRegion);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to populate Region filter list.");
                ViewBag.RegionFilterList = new SelectList(new List<string>()); 
            }
        }

        [HttpGet("AutocompleteStorageName")]
        public async Task<IActionResult> AutocompleteStorageName(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2) return Json(Enumerable.Empty<string>());
            var lowerTerm = term.ToLower();
            try
            {
                var matches = await _context.Storages
                    .Where(s => s.Name.ToLower().Contains(lowerTerm))
                    .OrderBy(s => s.Name)
                    .Select(s => s.Name)
                    .Take(10) 
                    .ToListAsync();
                return Json(matches);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during storage name autocomplete for term {Term}", term);
                return Json(Enumerable.Empty<string>());
            }
        }

        [HttpGet("AutocompleteCity")]
        public async Task<IActionResult> AutocompleteCity(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2) return Json(Enumerable.Empty<string>());
            var lowerTerm = term.ToLower();
            try
            {
                var matches = await _context.Storages
                    .Where(s => s.City.ToLower().Contains(lowerTerm))
                    .Select(s => s.City)
                    .Distinct()
                    .OrderBy(city => city)
                    .Take(10)
                    .ToListAsync();
                return Json(matches);
            }
            catch (Exception ex) { _logger.LogError(ex, "AutocompleteCity error"); return Json(Enumerable.Empty<string>()); }
        }

        [HttpGet("AutocompleteStreet")]
        public async Task<IActionResult> AutocompleteStreet(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2) return Json(Enumerable.Empty<string>());
            var lowerTerm = term.ToLower();
            try
            {
                var matches = await _context.Storages
                    .Where(s => s.StreetName != null && s.StreetName.ToLower().Contains(lowerTerm))
                    .Select(s => s.StreetName)
                    .Distinct()
                    .OrderBy(street => street)
                    .Take(10)
                    .ToListAsync();
                return Json(matches);
            }
            catch (Exception ex) { _logger.LogError(ex, "AutocompleteStreet error"); return Json(Enumerable.Empty<string>()); }
        }

        // GET: Storage/Details/НазваСкладу
        [HttpGet("Details/{name}")]
        public async Task<IActionResult> Details(
        string name,
        string activeTab = "info",
        int pPage = 1, 
        int kPage = 1, 
        int iPage = 1  
        )
        {
            if (string.IsNullOrEmpty(name)) return BadRequest();

            ViewData["Title"] = $"Деталі складу: {name}";
            ViewData["ActiveTab"] = activeTab;

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

                var productsQuery = _context.StorageProducts
                    .Where(sp => sp.StorageName == name)
                    .Include(sp => sp.ProductNameNavigation)
                        .ThenInclude(p => p.UnitCodeNavigation)
                    .OrderBy(sp => sp.ProductName)
                    .AsNoTracking();
                var pagedProducts = await productsQuery.ToPagedListAsync(pPage, _pageSize);

                var keepersQuery = _context.StorageKeepers
                    .Where(sk => sk.StorageName == name)
                    .Include(sk => sk.User)
                    .OrderBy(sk => sk.LastName).ThenBy(sk => sk.FirstName)
                    .AsNoTracking();
                var pagedKeepers = await keepersQuery.ToPagedListAsync(kPage, _pageSize);


                var senderInvoiceIds = await _context.Invoices
                                            .Where(i => i.SenderStorageName == name)
                                            .Select(i => i.InvoiceId)
                                            .ToListAsync();
                var receiverInvoiceIds = await _context.Invoices
                                            .Where(i => i.ReceiverStorageName == name)
                                            .Select(i => i.InvoiceId)
                                            .ToListAsync();

                var relatedInvoiceIds = senderInvoiceIds.Union(receiverInvoiceIds).Distinct().ToList();

                var invoicesQuery = _context.Invoices
                                    .Where(i => relatedInvoiceIds.Contains(i.InvoiceId))
                                    .Include(i => i.ListEntries)
                                    .AsNoTracking()
                                    .OrderByDescending(i => i.Date)
                                    .ThenByDescending(i => i.InvoiceId);
                var pagedInvoices = await invoicesQuery.ToPagedListAsync(iPage, _pageSize);

                var viewModel = new StorageDetailsViewModel
                {
                    Storage = storage, 
                    StorageProducts = pagedProducts,
                    StorageKeepers = pagedKeepers,
                    RelatedInvoices = pagedInvoices,
                    CurrentProductsPage = pPage,
                    CurrentKeepersPage = kPage,
                    CurrentInvoicesPage = iPage
                };

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