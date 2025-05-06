using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data; 
using IMS.Models;
using IMS.ViewModels;
using Microsoft.AspNetCore.Mvc.Rendering;
using System.Security.Claims;
using X.PagedList;
using X.PagedList.EF;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireStorageKeeperRole")]
    [Route("StorageProduct")]
    public class StorageProductController : Controller
    {
        private readonly AppDbContext _context;
        private readonly ILogger<StorageProductController> _logger;
        private const int _pageSize = 10;

        public StorageProductController(AppDbContext context, ILogger<StorageProductController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: StorageProduct
        [HttpGet("")]
        public async Task<IActionResult> Index(
        string? searchString = null,
        string? filterUnitName = null,
        bool filterLowStock = false,
        int page = 1)
        {
            ViewData["CurrentSearch"] = searchString;
            ViewData["CurrentUnitFilter"] = filterUnitName;
            ViewData["CurrentLowStockFilter"] = filterLowStock;

            try
            {
                var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
                bool isKeeper = User.IsInRole(UserRole.storage_keeper.ToString());
                bool isManagerOrOwner = User.IsInRole(UserRole.manager.ToString()) || User.IsInRole(UserRole.owner.ToString());

                if (isKeeper && !string.IsNullOrEmpty(userIdString))
                {
                    return await GetKeeperStockViewAsync(userIdString, searchString, filterUnitName, filterLowStock, page);
                }
                else if (isManagerOrOwner) 
                {
                    if (filterLowStock)
                    {
                        return await GetDetailedLowStockViewForManagerAsync(searchString, filterUnitName, page);
                    }
                    else
                    {
                        return await GetManagerStockSummaryViewAsync(searchString, filterUnitName, page);
                    }
                }
                else
                {
                    if (filterLowStock)
                    {
                        TempData["ErrorMessage"] = "Доступ заборонено.";
                        return RedirectToAction("Index", "Home");
                    }
                    return await GetManagerStockSummaryViewAsync(searchString, filterUnitName, page);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні залишків на складах (Index action)");
                TempData["ErrorMessage"] = "Не вдалося завантажити залишки.";
                return RedirectToAction("Index", "Home");
            }
        }

        // GET: StorageProduct/ByProduct/НазваТовару
        [HttpGet("StorageProduct/ByProduct/{productName}")]
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> DetailsByProduct(string productName)
        {
            if (string.IsNullOrEmpty(productName))
            {
                return NotFound("Назву товару не вказано.");
            }

            ViewData["Title"] = $"Залишки товару: {productName}";

            try
            {
                var stockDetails = await _context.StorageProducts
                    .Where(sp => sp.ProductName == productName)
                    .Include(sp => sp.StorageNameNavigation) 
                    .Include(sp => sp.ProductNameNavigation.UnitCodeNavigation) 
                    .OrderBy(sp => sp.StorageName)
                    .AsNoTracking()
                    .ToListAsync();

                if (!stockDetails.Any())
                {
                    bool productExists = await _context.Products.AnyAsync(p => p.ProductName == productName);
                    if (!productExists)
                    {
                        TempData["ErrorMessage"] = $"Товар з назвою '{productName}' не знайдено.";
                    }
                    else
                    {
                        TempData["InfoMessage"] = $"Товар '{productName}' відсутній на залишках на будь-якому складі.";
                    }
                    return RedirectToAction(nameof(Index));
                }

                string? unitName = stockDetails.First().ProductNameNavigation?.UnitCodeNavigation?.UnitName;

                var viewModel = new ProductStockDetailsViewModel
                {
                    ProductName = productName,
                    ProductUnitName = unitName,
                    StockDetails = stockDetails
                };

                return View("DetailsByProduct", viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей залишків для товару {ProductName}", productName);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталізацію залишків.";
                return RedirectToAction(nameof(Index));
            }
        }

        private async Task<IActionResult> GetKeeperStockViewAsync(string userIdString, string? searchString, string? filterUnitName, bool filterLowStock, int page) // Додано filterLowStock
        {
            ViewData["Title"] = "Поточні залишки на вашому складі";
            // ViewData фільтрів вже встановлено в Index

            IPagedList<StorageProduct> pagedKeeperStockList;

            if (int.TryParse(userIdString, out int userId))
            {
                var keeperStorageName = await _context.StorageKeepers
                    .Where(sk => sk.UserId == userId).Select(sk => sk.StorageName).FirstOrDefaultAsync();

                if (!string.IsNullOrEmpty(keeperStorageName))
                {
                    ViewData["Title"] = $"Залишки на складі: {keeperStorageName}";
                    var query = _context.StorageProducts
                        .Where(sp => sp.StorageName == keeperStorageName)
                        .Include(sp => sp.ProductNameNavigation.UnitCodeNavigation)
                        .AsNoTracking();

                    if (!string.IsNullOrEmpty(searchString))
                    {
                        query = query.Where(sp => sp.ProductName.ToLower().Contains(searchString.ToLower()));
                    }

                    if (!string.IsNullOrEmpty(filterUnitName))
                    {
                        query = query.Where(sp => sp.ProductNameNavigation.UnitCode == filterUnitName);
                    }

                    if (filterLowStock)
                    {
                        query = query.Where(sp => sp.MinimalCount > 0 && sp.Count <= sp.MinimalCount);
                        ViewData["Title"] = $"Низькі залишки на складі: {keeperStorageName}";
                    }

                    query = query.OrderBy(sp => sp.ProductName);

                    pagedKeeperStockList = await query.ToPagedListAsync(page, _pageSize);
                }
                else
                {
                    _logger.LogWarning("StorageKeeper with User ID {UserId} is not assigned to a storage.", userId);
                    TempData["InfoMessage"] = "Вам не призначено склад для перегляду залишків.";
                    pagedKeeperStockList = new PagedList<StorageProduct>(Enumerable.Empty<StorageProduct>(), page, _pageSize); 
                }
            }
            else
            {
                _logger.LogError("Could not parse User ID {UserIdString} for StorageKeeper filtering.", userIdString ?? "NULL");
                TempData["ErrorMessage"] = "Помилка визначення користувача.";
                pagedKeeperStockList = new PagedList<StorageProduct>(Enumerable.Empty<StorageProduct>(), page, _pageSize);
            }

            await PopulateUnitNameFilterList(filterUnitName);
            return View("IndexKeeper", pagedKeeperStockList);
        }

        private async Task<IActionResult> GetManagerStockSummaryViewAsync(string? searchString, string? filterUnitName, int page)
        {
            ViewData["Title"] = "Загальні залишки по товарах";

            var query = _context.StorageProducts.Include(sp => sp.ProductNameNavigation.UnitCodeNavigation).AsNoTracking();

            if (!string.IsNullOrEmpty(searchString))
            {
                query = query.Where(sp => sp.ProductName.ToLower().Contains(searchString.ToLower()));
            }

            if (!string.IsNullOrEmpty(filterUnitName))
            {
                query = query.Where(sp => sp.ProductNameNavigation.UnitCodeNavigation.UnitName == filterUnitName);
            }

            var summaryQuery = query
                .GroupBy(sp => new {
                    sp.ProductName,
                    sp.ProductNameNavigation.UnitCodeNavigation.UnitName
                })
                .Select(g => new ProductStockSummaryViewModel
                {
                    ProductName = g.Key.ProductName,
                    ProductUnitName = g.Key.UnitName,
                    TotalCount = g.Sum(sp => sp.Count),
                    TotalMinimal = g.Sum(sp => sp.MinimalCount)
                });

            var sortedSummaryQuery = summaryQuery.OrderBy(s => s.ProductName);

            var pagedSummaryList = await sortedSummaryQuery.ToPagedListAsync(page, _pageSize);

            await PopulateUnitNameFilterList(filterUnitName); 
            return View("IndexManager", pagedSummaryList); 
        }

        private async Task<IActionResult> GetDetailedLowStockViewForManagerAsync(string? searchString, string? filterUnitName, int page)
        {
            ViewData["Title"] = "Товари з низькими залишками (всі склади)"; 

            var query = _context.StorageProducts
                .AsNoTracking()
                .Include(sp => sp.StorageNameNavigation) 
                .Include(sp => sp.ProductNameNavigation)
                    .ThenInclude(p => p.UnitCodeNavigation) 
                .Where(sp => sp.MinimalCount > 0 && sp.Count <= sp.MinimalCount); 

            if (!string.IsNullOrEmpty(searchString))
            {
                query = query.Where(sp => sp.ProductName.ToLower().Contains(searchString.ToLower()));
            }
            if (!string.IsNullOrEmpty(filterUnitName))
            {
                query = query.Where(sp => sp.ProductNameNavigation.UnitCodeNavigation.UnitName == filterUnitName);
            }

            var sortedQuery = query.OrderBy(sp => sp.StorageName).ThenBy(sp => sp.ProductName);

            var pagedLowStockItems = await sortedQuery.ToPagedListAsync(page, _pageSize);

            await PopulateUnitNameFilterList(filterUnitName);

            return View("LowStockList", pagedLowStockItems);
        }


        // GET: StorageProduct/Add?storageName=Склад1 
        // GET: StorageProduct/Add 
        [Authorize(Roles = nameof(UserRole.owner))]
        public async Task<IActionResult> Add(string? storageName = null) 
        {
            var viewModel = new AddStorageProductViewModel();
            ViewData["Title"] = "Додати товар на склад";

            if (!string.IsNullOrEmpty(storageName))
            {
                var storageExists = await _context.Storages.AnyAsync(s => s.Name == storageName);
                if (!storageExists)
                {
                    TempData["ErrorMessage"] = $"Склад '{storageName}' не знайдено.";
                    return RedirectToAction("Index", "Storage");
                }

                viewModel.PreSelectedStorageName = storageName;
                ViewData["Title"] = $"Додати товар на склад '{storageName}'";
                await PopulateAvailableProductsForStorage(viewModel, storageName);
            }
            else
            {
                await PopulateAvailableStorages(viewModel);
                await PopulateAllProducts(viewModel);
            }

            return View("Add", viewModel);
        }


        // POST: StorageProduct/Add
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Add(AddStorageProductViewModel model)
        {
            string? targetStorageName = model.PreSelectedStorageName ?? model.SelectedStorageName;

            if (string.IsNullOrEmpty(targetStorageName))
            {
                ModelState.AddModelError("", "Не вдалося визначити цільовий склад.");
            }
            else if (string.IsNullOrEmpty(model.SelectedProductName))
            {
                ModelState.AddModelError("SelectedProductName", "Необхідно обрати товар.");
            }
            else
            {
                bool alreadyExists = await _context.StorageProducts.AnyAsync(sp => sp.StorageName == targetStorageName && sp.ProductName == model.SelectedProductName);
                if (alreadyExists)
                {
                    ModelState.AddModelError("SelectedProductName", $"Товар '{model.SelectedProductName}' вже додано на склад '{targetStorageName}'.");
                }
            }
            if (model.Count < 0) ModelState.AddModelError("Count", "Кількість не може бути від'ємною.");
            if (model.MinimalCount < 0) ModelState.AddModelError("MinimalCount", "Мінімальний залишок не може бути від'ємним.");


            if (ModelState.IsValid && !string.IsNullOrEmpty(targetStorageName))
            {
                var newStorageProduct = new StorageProduct
                {
                    StorageName = targetStorageName,
                    ProductName = model.SelectedProductName,
                    Count = model.Count,
                    MinimalCount = model.MinimalCount
                };

                var userName = User.Identity?.Name ?? "System";

                try
                {
                    _context.StorageProducts.Add(newStorageProduct);
                    await _context.SaveChangesAsync();

                    _logger.LogWarning(
                        "MANUAL STOCK ADD by {User}: Added Product '{ProductName}' to Storage '{StorageName}'. Initial Count: {Count}, Initial MinimalCount: {MinimalCount}.",
                        userName,
                        newStorageProduct.ProductName,
                        newStorageProduct.StorageName,
                        newStorageProduct.Count,
                        newStorageProduct.MinimalCount
                    );

                    TempData["SuccessMessage"] = $"Товар '{model.SelectedProductName}' успішно додано на склад '{targetStorageName}'.";
                    return RedirectToAction("Details", "Storage", new { name = targetStorageName }, "nav-stock");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка додавання товару {ProductName} на склад {StorageName}", model.SelectedProductName, targetStorageName);
                    ModelState.AddModelError("", "Не вдалося додати товар на склад.");
                }
            }

            await RepopulateAddViewModelDropdowns(model);
            ViewData["Title"] = string.IsNullOrEmpty(model.PreSelectedStorageName) ? "Додати товар на склад" : $"Додати товар на склад '{model.PreSelectedStorageName}'";
            return View(model);
        }

        // GET: Storage/Склад1/Product/Edit/Товар1
        [HttpGet("StorageProduct/Edit/{storageName}/{productName}")]
        [Authorize(Roles = nameof(UserRole.owner))]
        public async Task<IActionResult> Edit(string storageName, string productName)
        {
            if (string.IsNullOrEmpty(storageName) || string.IsNullOrEmpty(productName))
            {
                return NotFound("Не вказано склад або товар.");
            }

            var storageProduct = await _context.StorageProducts
                                                .Include(sp => sp.ProductNameNavigation)
                                                .ThenInclude(p => p.UnitCodeNavigation) 
                                                .FirstOrDefaultAsync(sp => sp.StorageName == storageName && sp.ProductName == productName);

            if (storageProduct == null)
            {
                TempData["ErrorMessage"] = $"Запис про залишки для товару '{productName}' на складі '{storageName}' не знайдено.";
                return RedirectToAction("Details", "Storage", new { name = storageName }, "nav-stock");
            }

            var viewModel = new EditStorageProductViewModel
            {
                StorageName = storageProduct.StorageName,
                ProductName = storageProduct.ProductName,
                ProductDisplayName = storageProduct.ProductNameNavigation?.ProductName,
                UnitName = storageProduct.ProductNameNavigation?.UnitCodeNavigation?.UnitName, 
                Count = storageProduct.Count,
                MinimalCount = storageProduct.MinimalCount,
                AdjustmentReason = ""
            };

            ViewData["Title"] = $"Редагувати залишки: {viewModel.ProductDisplayName ?? productName} на складі {storageName}";
            return View(viewModel);
        }

        // POST: Storage/Склад1/Product/Edit/Товар1
        [HttpPost("StorageProduct/Edit/{storageName}/{productName}")]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = nameof(UserRole.owner))]
        public async Task<IActionResult> Edit(string storageName, string productName, EditStorageProductViewModel model)
        {
            if (string.IsNullOrEmpty(storageName) || storageName != model.StorageName ||
                string.IsNullOrEmpty(productName) || productName != model.ProductName)
            {
                return BadRequest("Невідповідність ключів.");
            }

            if (model.Count < 0) ModelState.AddModelError("Count", "Кількість не може бути від'ємною.");
            if (model.MinimalCount < 0) ModelState.AddModelError("MinimalCount", "Мінімальний залишок не може бути від'ємним.");


            if (ModelState.IsValid)
            {
                var entityToUpdate = await _context.StorageProducts.FirstOrDefaultAsync(sp => sp.StorageName == storageName && sp.ProductName == productName);

                if (entityToUpdate == null)
                {
                    TempData["ErrorMessage"] = "Запис про залишки не знайдено (можливо, його видалили).";
                    return RedirectToAction("Details", "Storage", new { name = storageName }, "nav-stock");
                }

                var oldCount = entityToUpdate.Count;
                var oldMinimalCount = entityToUpdate.MinimalCount;
                var userName = User.Identity?.Name ?? "System";

                try
                {
                    entityToUpdate.Count = model.Count;
                    entityToUpdate.MinimalCount = model.MinimalCount;

                    _context.StorageProducts.Update(entityToUpdate);

                    await _context.SaveChangesAsync();

                    _logger.LogWarning(
                        "STOCK ADJUSTMENT by {User}: Product '{ProductName}' on Storage '{StorageName}'. Count changed from {OldCount} to {NewCount}. MinimalCount changed from {OldMinimalCount} to {NewMinimalCount}. Reason: {Reason}",
                        userName,
                        entityToUpdate.ProductName,
                        entityToUpdate.StorageName,
                        oldCount,
                        entityToUpdate.Count,
                        oldMinimalCount,
                        entityToUpdate.MinimalCount,
                        string.IsNullOrEmpty(model.AdjustmentReason) ? "N/A" : model.AdjustmentReason
                    );

                    TempData["SuccessMessage"] = $"Залишки товару '{model.ProductName}' на складі '{model.StorageName}' оновлено.";
                    return RedirectToAction("Details", "Storage", new { name = model.StorageName }, "nav-stock");
                }
                catch (DbUpdateConcurrencyException)
                {
                    if (!await _context.StorageProducts.AnyAsync(e => e.StorageName == storageName && e.ProductName == productName)) return NotFound();
                    else
                    {
                        _logger.LogWarning("Конфлікт паралельного доступу при оновленні залишків {ProductName} на {StorageName}", productName, storageName);
                        ModelState.AddModelError("", "Дані залишків були змінені іншим користувачем.");
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка оновлення залишків {ProductName} на {StorageName}", productName, storageName);
                    ModelState.AddModelError("", "Не вдалося оновити залишки.");
                }
            }

            var productInfo = await _context.Products
                                           .Include(p => p.UnitCodeNavigation)
                                           .AsNoTracking()
                                           .FirstOrDefaultAsync(p => p.ProductName == productName);
            model.ProductDisplayName = productInfo?.ProductName ?? productName;
            model.UnitName = productInfo?.UnitCodeNavigation?.UnitName;
            ViewData["Title"] = $"Редагувати залишки: {model.ProductDisplayName} на складі {storageName}";
            return View(model);
        }

        // GET: Storage/Склад1/Product/Delete/Товар1
        [Authorize(Roles = nameof(UserRole.owner))]
        public async Task<IActionResult> Delete(string storageName, string productName)
        {
            if (string.IsNullOrEmpty(storageName) || string.IsNullOrEmpty(productName))
            {
                return NotFound("Не вказано склад або товар.");
            }

            var storageProduct = await _context.StorageProducts
                                                .Include(sp => sp.ProductNameNavigation)
                                                .FirstOrDefaultAsync(sp => sp.StorageName == storageName && sp.ProductName == productName);

            if (storageProduct == null)
            {
                TempData["ErrorMessage"] = $"Запис про залишки для товару '{productName}' на складі '{storageName}' не знайдено.";
                return RedirectToAction("Details", "Storage", new { name = storageName }, "nav-stock");
            }

            ViewBag.WarningMessage = $"Увага! Ви збираєтеся повністю видалити запис про товар '{storageProduct.ProductNameNavigation?.ProductName ?? productName}' зі складу '{storageName}'. Поточний зареєстрований залишок: {storageProduct.Count}. Ця дія незворотня і може призвести до розбіжностей в обліку, якщо залишок не нульовий.";
            ViewBag.CanDelete = true;

            ViewData["Title"] = $"Видалити {storageProduct.ProductNameNavigation?.ProductName ?? productName} зі складу {storageName}";
            return View(storageProduct);
        }

        // POST: Storage/Склад1/Product/Delete/Товар1
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = nameof(UserRole.owner))]
        public async Task<IActionResult> DeleteConfirmed(string storageName, string productName)
        {
            if (string.IsNullOrEmpty(storageName) || string.IsNullOrEmpty(productName))
            {
                TempData["ErrorMessage"] = "Не вказано склад або товар для видалення.";
                return RedirectToAction("Index", "Storage");
            }

            try
            {
                var storageProduct = await _context.StorageProducts.FindAsync(productName, storageName);

                if (storageProduct == null)
                {
                    TempData["ErrorMessage"] = $"Запис про залишки товару '{productName}' на складі '{storageName}' не знайдено.";
                    return RedirectToAction("Details", "Storage", new { name = storageName }, "nav-stock");
                }

                var userName = User.Identity?.Name ?? "System";
                var currentCount = storageProduct.Count;

                _logger.LogWarning(
                    "MANUAL STOCK RECORD DELETE by {User}: Deleting StorageProduct entry for Product '{ProductName}' from Storage '{StorageName}'. Current Count was: {Count}.",
                    userName,
                    storageProduct.ProductName,
                    storageProduct.StorageName,
                    currentCount 
                );

                _context.StorageProducts.Remove(storageProduct);
                await _context.SaveChangesAsync();
                TempData["SuccessMessage"] = $"Товар '{productName}' успішно видалено зі складу '{storageName}'.";
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка видалення товару {ProductName} зі складу {StorageName}", productName, storageName);
                TempData["ErrorMessage"] = "Не вдалося видалити товар зі складу.";
            }

            return RedirectToAction("Details", "Storage", new { name = storageName }, "nav-stock");
        }

        [HttpPost("EditMinimalCountOnly")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> EditMinimalCountOnly(EditMinimalCountViewModel model)
        {
            decimal parsedMinimalCount = 0;
            var minimalCountString = Request.Form["MinimalCount"].FirstOrDefault();
            bool isParsed = decimal.TryParse(minimalCountString, 
                                            System.Globalization.NumberStyles.Any,
                                            System.Globalization.CultureInfo.InvariantCulture, 
                                            out parsedMinimalCount);

            if (!isParsed || parsedMinimalCount < 0)
            {
                ModelState.AddModelError(nameof(model.MinimalCount), "Некоректне значення мінімального залишку.");
            }
            else
            {
                model.MinimalCount = parsedMinimalCount; 
                                                        
                ModelState.Remove(nameof(model.MinimalCount));
            }

            if (ModelState.IsValid)
            {
                var entityToUpdate = await _context.StorageProducts
                                            .FirstOrDefaultAsync(sp => sp.StorageName == model.StorageName && sp.ProductName == model.ProductName);

                if (entityToUpdate == null)
                {
                    return Json(new { success = false, message = "Запис про залишки не знайдено." });
                }

                var oldMinimalCount = entityToUpdate.MinimalCount;
                var userName = User.Identity?.Name ?? "System";

                try
                {
                    entityToUpdate.MinimalCount = model.MinimalCount;

                    _context.StorageProducts.Update(entityToUpdate);
                    await _context.SaveChangesAsync();

                    _logger.LogInformation(
                        "MINIMAL COUNT UPDATE by {User}: Product '{ProductName}' on Storage '{StorageName}'. MinimalCount changed from {OldMinimalCount} to {NewMinimalCount}.",
                        userName, entityToUpdate.ProductName, entityToUpdate.StorageName, oldMinimalCount, entityToUpdate.MinimalCount
                    );

                    return Json(new { success = true, newMinimalCount = entityToUpdate.MinimalCount });
                }
                catch (DbUpdateConcurrencyException)
                {
                    _logger.LogWarning("Конфлікт паралельного доступу при оновленні MinimalCount {ProductName} на {StorageName}", model.ProductName, model.StorageName);
                    return Json(new { success = false, message = "Дані були змінені іншим користувачем. Оновіть сторінку." });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка оновлення MinimalCount {ProductName} на {StorageName}", model.ProductName, model.StorageName);
                    return Json(new { success = false, message = "Не вдалося оновити мінімальний залишок." });
                }
            }

            var errors = ModelState.Values.SelectMany(v => v.Errors).Select(e => e.ErrorMessage).ToList();
            return Json(new { success = false, message = "Помилка валідації.", errors = errors });
        }

        private async Task PopulateAvailableProductsForStorage(AddStorageProductViewModel viewModel, string storageName)
        {
            var productsInStock = _context.StorageProducts
                                       .Where(sp => sp.StorageName == storageName)
                                       .Select(sp => sp.ProductName);
            var availableProductsQuery = _context.Products
                                            .Where(p => !productsInStock.Contains(p.ProductName))
                                            .OrderBy(p => p.ProductName);
            viewModel.AvailableProducts = new SelectList(await availableProductsQuery.AsNoTracking().ToListAsync(), "ProductName", "ProductName", viewModel.SelectedProductName);
        }

        private async Task PopulateUnitNameFilterList(string? selectedUnitName)
        {
            var unitNames = await _context.ProductUnits
                                         .OrderBy(pu => pu.UnitName)
                                         .Select(pu => pu.UnitName)
                                         .Distinct()
                                         .ToListAsync();
            ViewBag.UnitNameFilterList = new SelectList(unitNames.Select(n => new { Value = n, Text = n }), "Value", "Text", selectedUnitName);
        }

        [HttpGet("AutocompleteStockProductName")]
        public async Task<IActionResult> AutocompleteStockProductName(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2)
            {
                return Json(Enumerable.Empty<string>());
            }
            var lowerTerm = term.ToLower();

            try
            {
                var query = _context.StorageProducts.AsQueryable();

                if (User.IsInRole(UserRole.storage_keeper.ToString()) && int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out int userId))
                {
                    var keeperStorageName = await _context.StorageKeepers
                       .Where(sk => sk.UserId == userId)
                       .Select(sk => sk.StorageName)
                       .FirstOrDefaultAsync();
                    if (!string.IsNullOrEmpty(keeperStorageName))
                    {
                        query = query.Where(sp => sp.StorageName == keeperStorageName);
                    }
                    else 
                    {
                        return Json(Enumerable.Empty<string>());
                    }
                }

                var matches = await query
                    .Where(sp => sp.ProductName.ToLower().Contains(lowerTerm))
                    .Select(sp => sp.ProductName)
                    .Distinct()
                    .OrderBy(name => name)
                    .Take(10)
                    .ToListAsync();

                return Json(matches);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during stock product name autocomplete for term {Term}", term);
                return Json(Enumerable.Empty<string>());
            }
        }


        private async Task PopulateAvailableStorages(AddStorageProductViewModel viewModel)
        {
            var storagesQuery = _context.Storages.OrderBy(s => s.Name);
            viewModel.AvailableStorages = new SelectList(await storagesQuery.AsNoTracking().ToListAsync(), "Name", "Name", viewModel.SelectedStorageName);
        }

        private async Task PopulateAllProducts(AddStorageProductViewModel viewModel)
        {
            var productsQuery = _context.Products.OrderBy(p => p.ProductName);
            viewModel.AvailableProducts = new SelectList(await productsQuery.AsNoTracking().ToListAsync(), "ProductName", "ProductName", viewModel.SelectedProductName);
        }

        private async Task RepopulateAddViewModelDropdowns(AddStorageProductViewModel model)
        {
            if (!string.IsNullOrEmpty(model.PreSelectedStorageName))
            {
                await PopulateAvailableProductsForStorage(model, model.PreSelectedStorageName);
            }
            else
            {
                await PopulateAvailableStorages(model);
                await PopulateAllProducts(model);
            }
        }
    }
}