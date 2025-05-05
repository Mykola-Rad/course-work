using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization; 
using Microsoft.EntityFrameworkCore; 
using IMS.Data; 
using IMS.Models;
using Microsoft.AspNetCore.Mvc.Rendering;
using Npgsql;
using X.PagedList.EF;
using IMS.ViewModels;
using X.PagedList;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireStorageKeeperRole")]
    public class ProductController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<ProductController> _logger;
        private const int _pageSize = 10;

        public ProductController(AppDbContext context, ILogger<ProductController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: Product або Product/Index
        public async Task<IActionResult> Index(string? searchString, string? filterUnitCode, int page = 1) 
        {
            ViewData["Title"] = "Довідник товарів";
            ViewData["CurrentNameFilter"] = searchString;
            ViewData["CurrentUnitFilter"] = filterUnitCode;

            int pageNumber = page; 

            try
            {
                var productsQuery = _context.Products
                                            .Include(p => p.UnitCodeNavigation)
                                            .AsNoTracking() 
                                            .AsQueryable();

                if (!string.IsNullOrEmpty(searchString))
                {
                    productsQuery = productsQuery.Where(p => p.ProductName.ToLower().Contains(searchString.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterUnitCode))
                {
                    productsQuery = productsQuery.Where(p => p.UnitCode == filterUnitCode);
                }

                productsQuery = productsQuery.OrderBy(p => p.ProductName);

                var pagedProducts = await productsQuery.ToPagedListAsync(pageNumber, _pageSize);

                var units = await _context.ProductUnits.OrderBy(pu => pu.UnitName).ToListAsync();
                ViewBag.UnitCodeFilterList = new SelectList(units, "UnitCode", "UnitName", filterUnitCode);

                return View(pagedProducts);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку товарів");
                TempData["ErrorMessage"] = "Не вдалося завантажити список товарів.";
                ViewBag.UnitCodeFilterList = new SelectList(await _context.ProductUnits.OrderBy(pu => pu.UnitName).ToListAsync(), "UnitCode", "UnitName", filterUnitCode);
                return View(new List<Product>()); 
            }
        }

        // GET: Product/Details/НазваТовару
        public async Task<IActionResult> Details(
        string productName,
        string activeTab = "info", 
        int cPage = 1,             
        int sPage = 1             
        )
        {
            if (string.IsNullOrEmpty(productName)) return NotFound();

            ViewData["ActiveTab"] = activeTab; 

            try
            {
                var product = await _context.Products
                    .Include(p => p.UnitCodeNavigation)
                    .AsNoTracking()
                    .FirstOrDefaultAsync(p => p.ProductName == productName);

                if (product == null)
                {
                    _logger.LogWarning("Спроба перегляду деталей неіснуючого товару: {ProductName}", productName);
                    TempData["ErrorMessage"] = $"Товар '{productName}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                ViewData["Title"] = $"Деталі товару: {product.ProductName}";

                var viewModel = new ProductDetailsViewModel
                {
                    Product = product,
                    CurrentCustomersPage = cPage,
                    CurrentSuppliersPage = sPage,
                    Customers = null,
                    Suppliers = null
                };

                bool canSeeRelated = User.IsInRole(UserRole.manager.ToString()) || User.IsInRole(UserRole.owner.ToString());

                if (canSeeRelated)
                {
                    var customerNamesQuery = _context.ListEntries
                        .Where(le => le.ProductName == productName && le.Invoice.Type == InvoiceType.release && le.Invoice.CounterpartyName != null)
                        .Select(le => le.Invoice.CounterpartyName)
                        .Distinct();

                    var customersQuery = _context.Counterparties
                        .Where(cp => customerNamesQuery.Contains(cp.Name)) 
                        .OrderBy(cp => cp.Name);
                    viewModel.Customers = await customersQuery.ToPagedListAsync(cPage, _pageSize);


                    var supplierNamesQuery = _context.ListEntries
                         .Where(le => le.ProductName == productName && le.Invoice.Type == InvoiceType.supply && le.Invoice.CounterpartyName != null)
                         .Select(le => le.Invoice.CounterpartyName)
                         .Distinct();

                    var suppliersQuery = _context.Counterparties
                        .Where(cp => supplierNamesQuery.Contains(cp.Name))
                        .OrderBy(cp => cp.Name);
                    viewModel.Suppliers = await suppliersQuery.ToPagedListAsync(sPage, _pageSize);
                }
                else
                {
                    viewModel.Customers = new PagedList<Counterparty>(Enumerable.Empty<Counterparty>(), cPage, _pageSize);
                    viewModel.Suppliers = new PagedList<Counterparty>(Enumerable.Empty<Counterparty>(), sPage, _pageSize);
                }

                return View(viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей товару {ProductName}", productName);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталі товару.";
                return RedirectToAction(nameof(Index));
            }
        }

        // GET: Product/Create
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> Create()
        {
            await PopulateProductUnitsDropDownList();
            return View();
        }

        // POST: Product/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Create([Bind("ProductName,UnitCode,LastPrice")] Product product)
        {
            if (await _context.Products.AnyAsync(p => p.ProductName == product.ProductName))
            {
                ModelState.AddModelError("ProductName", "Товар з такою назвою вже існує.");
            }
            if (product.LastPrice <= 0)
            {
                ModelState.AddModelError("LastPrice", "Ціна товару повинна бути більше нуля.");
            }

            ModelState.Remove(nameof(Product.UnitCodeNavigation));
            if (ModelState.IsValid)
            {
                try
                {
                    _context.Add(product);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Товар '{product.ProductName}' успішно створено.";
                    return RedirectToAction(nameof(Index));
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при створенні товару {ProductName}", product.ProductName);
                    ModelState.AddModelError("", "Не вдалося створити товар. Спробуйте ще раз.");
                }
            }

            await PopulateProductUnitsDropDownList(product.UnitCode);
            return View(product);
        }

        // GET: Product/Edit/НазваТовару
        [HttpGet("Product/Edit/{productName}")]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Edit(string productName)
        {
            if (string.IsNullOrEmpty(productName))
            {
                return NotFound();
            }

            var product = await _context.Products.FindAsync(productName);

            if (product == null)
            {
                return NotFound();
            }

            await PopulateProductUnitsDropDownList(product.UnitCode);
            ViewBag.OriginalProductName = productName;
            return View(product);
        }

        // POST: Product/Edit/НазваТовару
        [HttpPost("Product/Edit/{productName}")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Edit([FromRoute] string productName, [Bind("ProductName,UnitCode,LastPrice")] Product productFromForm)
        {
            if (string.IsNullOrEmpty(productName))
            {
                return BadRequest("Original product name is required.");
            }

            if (productName != productFromForm.ProductName && await ProductExists(productFromForm.ProductName))
            {
                ModelState.AddModelError("ProductName", "Товар з такою новою назвою вже існує.");
            }

            var productToUpdate = await _context.Products.FirstOrDefaultAsync(p => p.ProductName == productName);
            if (productToUpdate == null)
            {
                TempData["ErrorMessage"] = "Товар, який ви намагаєтесь редагувати, було змінено або видалено.";
                return RedirectToAction(nameof(Index));
            }

            ModelState.Remove(nameof(Product.UnitCodeNavigation));
            if (ModelState.IsValid)
            {
                string sql = @"UPDATE public.product
                        SET product_name = {0}, unit_code = {1}, last_price = {2}
                        WHERE product_name = {3}";
                try
                {
                    int affectedRows = await _context.Database.ExecuteSqlRawAsync(sql,
                        productFromForm.ProductName, 
                        productFromForm.UnitCode,    
                        productFromForm.LastPrice,   
                        productName                  
                    );

                    if (affectedRows > 0)
                    {
                        TempData["SuccessMessage"] = $"Товар '{productFromForm.ProductName}' успішно оновлено.";
                        return RedirectToAction(nameof(Index));
                    }
                    else
                    {
                        _logger.LogWarning("Спроба оновлення неіснуючого товару (ориг. назва {OriginalProductName}) через Raw SQL", productName);
                        TempData["ErrorMessage"] = "Товар, який ви намагаєтесь редагувати, не знайдено.";
                        return RedirectToAction(nameof(Index));
                    }
                }
                catch (Exception ex) 
                {
                    _logger.LogError(ex, "Помилка при оновленні товару (ориг. назва {OriginalProductName}) через Raw SQL", productName);
                    ModelState.AddModelError("", "Не вдалося оновити товар. Спробуйте ще раз.");
                    if (ex.InnerException is PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation)
                    {
                        ModelState.AddModelError("ProductName", "Товар з такою новою назвою вже існує (конфлікт БД).");
                    }
                }
            }

            await PopulateProductUnitsDropDownList(productFromForm.UnitCode);
            ViewBag.OriginalProductName = productName;
            return View(productFromForm);
        }

        // GET: Product/Delete/НазваТовару
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Delete(string productName)
        {
            if (string.IsNullOrEmpty(productName))
            {
                return NotFound();
            }

            try
            {
                var product = await _context.Products
                                            .Include(p => p.UnitCodeNavigation)
                                            .FirstOrDefaultAsync(m => m.ProductName == productName);
                if (product == null)
                {
                    return NotFound();
                }

                bool isInStock = await _context.StorageProducts.AnyAsync(sp => sp.ProductName == productName);
                bool isInInvoices = await _context.ListEntries.AnyAsync(le => le.ProductName == productName);

                if (isInStock)
                {
                    ViewData["WarningMessage"] = "Увага! Цей товар є на залишках на одному чи декількох складах.";
                }
                if (isInInvoices)
                {
                    ViewData["WarningMessage"] = (ViewData["WarningMessage"] ?? "") + " Увага! Цей товар фігурує в існуючих накладних.";
                }

                return View(product); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при підготовці до видалення товару {ProductName}", productName);
                TempData["ErrorMessage"] = "Не вдалося відкрити сторінку видалення товару.";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: Product/Delete/НазваТовару
        [HttpPost, ActionName("Delete")] 
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> DeleteConfirmed(string productName)
        {
            if (string.IsNullOrEmpty(productName))
            {
                return NotFound();
            }

            try
            {
                bool isInStock = await _context.StorageProducts.AnyAsync(sp => sp.ProductName == productName);
                bool isInInvoices = await _context.ListEntries.AnyAsync(le => le.ProductName == productName);

                if (isInStock || isInInvoices)
                {
                    _logger.LogWarning("Спроба видалення товару '{ProductName}', що має залежності.", productName);
                    TempData["ErrorMessage"] = "Неможливо видалити товар, оскільки він наявний на залишках та/або в документах.";
                    return RedirectToAction(nameof(Index));
                }

                var product = await _context.Products.FindAsync(productName);
                if (product != null)
                {
                    _context.Products.Remove(product);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Товар '{product.ProductName}' успішно видалено.";
                }
                else
                {
                    TempData["ErrorMessage"] = "Товар для видалення не знайдено.";
                }
                return RedirectToAction(nameof(Index));
            }
            catch (DbUpdateException ex)
            {
                _logger.LogError(ex, "Помилка видалення товару {ProductName} через конфлікт БД.", productName);
                TempData["ErrorMessage"] = "Не вдалося видалити товар через конфлікт у базі даних. Перевірте пов'язані записи.";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Загальна помилка при видаленні товару {ProductName}", productName);
                TempData["ErrorMessage"] = "Не вдалося видалити товар.";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpGet]
        public async Task<IActionResult> Autocomplete(string term)
        {
            if (string.IsNullOrWhiteSpace(term))
                return Json(Enumerable.Empty<string>());

            var matches = await _context.Products
                .Where(p => p.ProductName.ToLower().Contains(term.ToLower()))
                .OrderBy(p => p.ProductName)
                .Select(p => p.ProductName)
                .Take(10)
                .ToListAsync();

            return Json(matches);
        }

        private async Task<bool> ProductExists(string productName)
        {
            return await _context.Products.AnyAsync(e => e.ProductName == productName);
        }

        private async Task PopulateProductUnitsDropDownList(object? selectedUnit = null)
        {
            var unitsQuery = from u in _context.ProductUnits
                             orderby u.UnitName
                             select u;
            ViewBag.UnitCode = new SelectList(await unitsQuery.AsNoTracking().ToListAsync(), "UnitCode", "UnitName", selectedUnit);
        }

    }
}