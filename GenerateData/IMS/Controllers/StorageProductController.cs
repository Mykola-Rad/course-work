using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data; 
using IMS.Models;
using IMS.ViewModels;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireManagerRole")]
    public class StorageProductController : Controller
    {
        private readonly AppDbContext _context;
        private readonly ILogger<StorageProductController> _logger;

        public StorageProductController(AppDbContext context, ILogger<StorageProductController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: StorageProduct/Add?storageName=Склад1 
        // GET: StorageProduct/Add 
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

                try
                {
                    _context.StorageProducts.Add(newStorageProduct);
                    await _context.SaveChangesAsync();
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
                MinimalCount = storageProduct.MinimalCount
            };

            ViewData["Title"] = $"Редагувати залишки: {viewModel.ProductDisplayName ?? productName} на складі {storageName}";
            return View(viewModel);
        }

        // POST: Storage/Склад1/Product/Edit/Товар1
        [HttpPost("StorageProduct/Edit/{storageName}/{productName}")]
        [ValidateAntiForgeryToken]
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

                try
                {
                    entityToUpdate.Count = model.Count;
                    entityToUpdate.MinimalCount = model.MinimalCount;

                    _context.StorageProducts.Update(entityToUpdate);

                    await _context.SaveChangesAsync();
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

            ViewData["Title"] = $"Видалити {storageProduct.ProductNameNavigation?.ProductName ?? productName} зі складу {storageName}";
            return View(storageProduct);
        }

        // POST: Storage/Склад1/Product/Delete/Товар1
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
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