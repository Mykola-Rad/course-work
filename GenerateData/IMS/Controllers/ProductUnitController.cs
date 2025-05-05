using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data;
using IMS.Models;
using Npgsql;
using X.PagedList.EF;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireManagerRole")]
    [Route("ProductUnits")]
    public class ProductUnitController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<ProductUnitController> _logger;
        private const int _pageSize = 10;

        public ProductUnitController(AppDbContext context, ILogger<ProductUnitController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: ProductUnits або ProductUnits/Index
        [HttpGet("")]
        public async Task<IActionResult> Index(string? searchString, int page = 1)
        {
            ViewData["Title"] = "Одиниці виміру";
            ViewData["CurrentFilter"] = searchString;
            int pageNumber = page;
            try
            {
                var unitsQuery = _context.ProductUnits.AsQueryable();

                if (!string.IsNullOrEmpty(searchString))
                {
                    string lowerSearch = searchString.ToLower();
                    unitsQuery = unitsQuery.Where(u => u.UnitCode.ToLower().Contains(lowerSearch)
                                                   || u.UnitName.ToLower().Contains(lowerSearch));
                }

                unitsQuery = unitsQuery.OrderBy(u => u.UnitName);

                var pagedUnits = await unitsQuery.ToPagedListAsync(pageNumber, _pageSize);
                return View(pagedUnits);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку одиниць виміру з пошуком");
                TempData["ErrorMessage"] = "Не вдалося завантажити список одиниць виміру.";
                return View(new List<ProductUnit>());
            }
        }

        [HttpGet("Autocomplete")]
        public async Task<IActionResult> Autocomplete(string term)
        {
            if (string.IsNullOrWhiteSpace(term))
            {
                return Json(Enumerable.Empty<string>());
            }

            var lowerTerm = term.ToLower();

            try
            {
                var matches = await _context.ProductUnits
                    .Where(u => u.UnitCode.ToLower().Contains(lowerTerm) || u.UnitName.ToLower().Contains(lowerTerm))
                    .OrderBy(u => u.UnitName)
                    .Select(u => $"{u.UnitName} ({u.UnitCode})") 
                    .Take(10) 
                    .ToListAsync();

                return Json(matches);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка автозаповнення для одиниць виміру з терміном {Term}", term);
                return Json(Enumerable.Empty<string>());
            }
        }

        // GET: ProductUnits/Create
        [HttpGet("Create")]
        public IActionResult Create()
        {
            return View();
        }

        // POST: ProductUnits/Create
        [HttpPost("Create")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create([Bind("UnitCode,UnitName")] ProductUnit productUnit)
        {
            if (await _context.ProductUnits.AnyAsync(pu => pu.UnitCode == productUnit.UnitCode))
            {
                ModelState.AddModelError("UnitCode", $"Код одиниці '{productUnit.UnitCode}' вже існує.");
            }

            ModelState.Remove(nameof(ProductUnit.Products));

            if (ModelState.IsValid)
            {
                try
                {
                    _context.Add(productUnit);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Одиницю виміру '{productUnit.UnitName}' ({productUnit.UnitCode}) успішно створено.";
                    return RedirectToAction(nameof(Index));
                }
                catch (DbUpdateException ex) 
                {
                    _logger.LogError(ex, "Помилка при створенні одиниці виміру {UnitCode}", productUnit.UnitCode);
                    ModelState.AddModelError("", "Не вдалося створити одиницю виміру. Перевірте введені дані.");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при створенні одиниці виміру {UnitCode}", productUnit.UnitCode);
                    ModelState.AddModelError("", "Не вдалося створити одиницю виміру.");
                }
            }

            return View(productUnit);
        }

        // GET: ProductUnits/Edit/kg
        [HttpGet("Edit/{unitCode}")]
        public async Task<IActionResult> Edit(string unitCode)
        {
            if (string.IsNullOrEmpty(unitCode)) return BadRequest();

            var productUnit = await _context.ProductUnits.FindAsync(unitCode);
            if (productUnit == null) return NotFound();

            ViewData["Title"] = $"Редагувати одиницю: {productUnit.UnitName} ({unitCode})";
            ViewBag.OriginalUnitCode = unitCode;
            return View(productUnit);
        }

        // POST: ProductUnits/Edit/СтарийКод
        [HttpPost("Edit/{originalUnitCode}")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit([FromRoute] string originalUnitCode, [Bind("UnitCode,UnitName")] ProductUnit productUnitFromForm)
        {
            if (string.IsNullOrEmpty(originalUnitCode)) return BadRequest("Original unit code not provided.");
            if (productUnitFromForm == null) return BadRequest("Form data missing.");

            if (originalUnitCode != productUnitFromForm.UnitCode && await ProductUnitExists(productUnitFromForm.UnitCode))
            {
                ModelState.AddModelError("UnitCode", $"Код одиниці '{productUnitFromForm.UnitCode}' вже існує.");
            }

            ModelState.Remove(nameof(ProductUnit.Products));

            if (ModelState.IsValid)
            {
                string sql = @"UPDATE public.product_units
                        SET unit_code = {0}, unit_name = {1}
                        WHERE unit_code = {2}";
                try
                {
                    int affectedRows = await _context.Database.ExecuteSqlRawAsync(sql,
                        productUnitFromForm.UnitCode, 
                        productUnitFromForm.UnitName, 
                        originalUnitCode              
                    );

                    if (affectedRows > 0)
                    {
                        TempData["SuccessMessage"] = $"Одиницю виміру '{productUnitFromForm.UnitName}' ({productUnitFromForm.UnitCode}) успішно оновлено.";
                        return RedirectToAction(nameof(Index));
                    }
                    else
                    {
                        _logger.LogWarning("Спроба оновлення неіснуючої одиниці виміру (ориг. код {OriginalUnitCode})", originalUnitCode);
                        TempData["ErrorMessage"] = "Одиниця виміру, яку ви намагаєтесь редагувати, не знайдена.";
                        return RedirectToAction(nameof(Index));
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при оновленні одиниці виміру (ориг. код {OriginalUnitCode}) через Raw SQL", originalUnitCode);
                    ModelState.AddModelError("", "Не вдалося оновити одиницю виміру.");
                    if (ex.InnerException is Npgsql.PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation)
                    {
                        ModelState.AddModelError("UnitCode", "Код одиниці виміру має бути унікальним (конфлікт БД).");
                    }
                }
            }

            ViewData["Title"] = $"Редагувати одиницю: {originalUnitCode} (Помилка)";
            ViewBag.OriginalUnitCode = originalUnitCode; 
            return View(productUnitFromForm); 
        }

        // GET: ProductUnits/Delete/kg
        [HttpGet("Delete/{unitCode}")]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Delete(string unitCode)
        {
            if (string.IsNullOrEmpty(unitCode)) return NotFound();

            var productUnit = await _context.ProductUnits.FindAsync(unitCode);
            if (productUnit == null) return NotFound();

            ViewData["Title"] = $"Видалити: {productUnit.UnitName} ({unitCode})";

            bool isUsed = await _context.Products.AnyAsync(p => p.UnitCode == unitCode);
            ViewBag.CanDelete = !isUsed;
            if (isUsed)
            {
                ViewBag.WarningMessage = "Неможливо видалити: ця одиниця виміру використовується в одному чи декількох товарах.";
            }

            return View(productUnit);
        }

        // POST: ProductUnits/Delete/kg
        [HttpPost("Delete/{unitCode}"), ActionName("Delete")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> DeleteConfirmed(string unitCode)
        {
            if (string.IsNullOrEmpty(unitCode)) return NotFound();

            bool isUsed = await _context.Products.AnyAsync(p => p.UnitCode == unitCode);
            if (isUsed)
            {
                TempData["ErrorMessage"] = "Неможливо видалити одиницю виміру, оскільки вона використовується товарами.";
                return RedirectToAction(nameof(Index));
            }

            var productUnit = await _context.ProductUnits.FindAsync(unitCode);
            if (productUnit != null)
            {
                try
                {
                    _context.ProductUnits.Remove(productUnit);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Одиницю виміру '{productUnit.UnitName}' ({productUnit.UnitCode}) успішно видалено.";
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при видаленні одиниці виміру {UnitCode}", unitCode);
                    TempData["ErrorMessage"] = "Не вдалося видалити одиницю виміру.";
                }
            }
            else
            {
                TempData["ErrorMessage"] = "Одиницю виміру не знайдено.";
            }
            return RedirectToAction(nameof(Index));
        }



        // Допоміжний метод перевірки існування
        private async Task<bool> ProductUnitExists(string unitCode)
        {
            return await _context.ProductUnits.AnyAsync(e => e.UnitCode == unitCode);
        }

    }
}