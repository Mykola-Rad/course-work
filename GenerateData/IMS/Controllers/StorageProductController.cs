using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data; 
using IMS.Models;
using IMS.ViewModels;
using Microsoft.AspNetCore.Mvc.Rendering;
using System.Security.Cryptography.X509Certificates;
using System.Security.Claims;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireManagerRole")]
    [Route("StorageProduct")]
    public class StorageProductController : Controller
    {
        private readonly AppDbContext _context;
        private readonly ILogger<StorageProductController> _logger;

        public StorageProductController(AppDbContext context, ILogger<StorageProductController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: StorageProduct
        [HttpGet("")]
        [AllowAnonymous]
        public async Task<IActionResult> Index()
        {
            try
            {
                var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
                bool isKeeper = User.IsInRole(UserRole.storage_keeper.ToString());

                if (isKeeper) 
                {
                    return await GetKeeperStockViewAsync(userIdString); 
                }
                else 
                {
                    return await GetManagerStockSummaryViewAsync(); 
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

        private async Task<IActionResult> GetKeeperStockViewAsync(string? userIdString)
        {
            ViewData["Title"] = "Поточні залишки на вашому складі";
            List<StorageProduct> keeperStockList = new List<StorageProduct>(); 

            if (int.TryParse(userIdString, out int userId))
            {
                var keeperStorageName = await _context.StorageKeepers
                                                      .Where(sk => sk.UserId == userId)
                                                      .Select(sk => sk.StorageName)
                                                      .FirstOrDefaultAsync();

                if (!string.IsNullOrEmpty(keeperStorageName))
                {
                    ViewData["Title"] = $"Залишки на складі: {keeperStorageName}";
                    keeperStockList = await _context.StorageProducts
                        .Where(sp => sp.StorageName == keeperStorageName)
                        .Include(sp => sp.ProductNameNavigation.UnitCodeNavigation)
                        .OrderBy(sp => sp.ProductName)
                        .AsNoTracking()
                        .ToListAsync();
                }
                else
                {
                    _logger.LogWarning("StorageKeeper with User ID {UserId} is not assigned to a storage.", userId);
                    TempData["InfoMessage"] = "Вам не призначено склад для перегляду залишків."; 
                }
            }
            else
            {
                _logger.LogError("Could not parse User ID {UserIdString} for StorageKeeper filtering.", userIdString ?? "NULL");
                TempData["ErrorMessage"] = "Помилка визначення користувача.";
            }
            return View("IndexKeeper", keeperStockList);
        }

        private async Task<IActionResult> GetManagerStockSummaryViewAsync()
        {
            ViewData["Title"] = "Загальні залишки по товарах";

            var summaryList = await _context.StorageProducts
                .Include(sp => sp.ProductNameNavigation.UnitCodeNavigation)
                .GroupBy(sp => new {
                    sp.ProductName,
                    UnitName = sp.ProductNameNavigation.UnitCodeNavigation.UnitName
                })
                .Select(g => new ProductStockSummaryViewModel
                {
                    ProductName = g.Key.ProductName,
                    ProductUnitName = g.Key.UnitName,
                    TotalCount = g.Sum(sp => sp.Count)
                })
                .OrderBy(s => s.ProductName)
                .AsNoTracking()
                .ToListAsync();

            return View("IndexManager", summaryList);
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
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> EditMinimalCountOnly(EditMinimalCountViewModel model)
        {
            // --- Повертаємо Ручний Парсинг і Валідацію MinimalCount ---
            decimal parsedMinimalCount = 0;
            var minimalCountString = Request.Form["MinimalCount"].FirstOrDefault();
            bool isParsed = decimal.TryParse(minimalCountString, // Рядок вже має містити крапку завдяки JS
                                            System.Globalization.NumberStyles.Any,
                                            System.Globalization.CultureInfo.InvariantCulture, // Очікуємо крапку
                                            out parsedMinimalCount);

            if (!isParsed || parsedMinimalCount < 0)
            {
                ModelState.AddModelError(nameof(model.MinimalCount), "Некоректне значення мінімального залишку.");
            }
            else
            {
                model.MinimalCount = parsedMinimalCount; // Записуємо коректне значення
                                                         // Видаляємо помилку від стандартного біндера, якщо вона була
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