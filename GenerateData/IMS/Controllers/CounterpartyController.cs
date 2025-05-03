using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data;
using IMS.Models;
using Npgsql;
using IMS.ViewModels;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireManagerRole")]
    [Route("Counterparties")]
    public class CounterpartyController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<CounterpartyController> _logger;

        public CounterpartyController(AppDbContext context, ILogger<CounterpartyController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: Counterparties
        [HttpGet("")]
        public async Task<IActionResult> Index()
        {
            ViewData["Title"] = "Контрагенти";
            try
            {
                var counterparties = await _context.Counterparties
                                                    .Include(c => c.Roles)
                                                   .OrderBy(c => c.Name)
                                                   .ToListAsync();
                return View(counterparties);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку контрагентів");
                TempData["ErrorMessage"] = "Не вдалося завантажити список контрагентів.";
                return View(new List<Counterparty>());
            }
        }

        // GET: Counterparties/Create
        [HttpGet("Create")]
        public async Task<IActionResult> Create()
        {
            ViewData["Title"] = "Створити контрагента";
            var allRoles = await _context.CounterpartyRoles.OrderBy(r => r.Name).ToListAsync();

            var viewModel = new CounterpartyViewModel
            {
                RolesCheckboxes = allRoles.Select(r => new RoleCheckboxViewModel
                {
                    Id = r.RoleId,
                    Name = r.Name,
                    IsAssigned = false 
                }).ToList()
            };

            return View(viewModel);
        }

        // POST: Counterparties/Create
        [HttpPost("Create")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(CounterpartyViewModel model) 
        {
            if (await CounterpartyExists(model.Name))
            {
                ModelState.AddModelError("Name", $"Контрагент з назвою '{model.Name}' вже існує.");
            }

            if (ModelState.IsValid)
            {
                var counterparty = new Counterparty
                {
                    Name = model.Name,
                    PhoneNumber = model.PhoneNumber,
                    Email = model.Email
                };

                using var transaction = await _context.Database.BeginTransactionAsync(); 
                try
                {
                    _context.Counterparties.Add(counterparty);
                    await _context.SaveChangesAsync(); 

                    if (model.SelectedRoleIds != null && model.SelectedRoleIds.Any())
                    {
                        var rolesToAdd = await _context.CounterpartyRoles
                                                       .Where(r => model.SelectedRoleIds.Contains(r.RoleId))
                                                       .ToListAsync();
                        
                        foreach (var role in rolesToAdd)
                        {
                            counterparty.Roles.Add(role);
                        }
                        await _context.SaveChangesAsync(); 
                    }

                    await transaction.CommitAsync();
                    TempData["SuccessMessage"] = $"Контрагента '{counterparty.Name}' успішно створено.";
                    return RedirectToAction(nameof(Index));
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync(); 
                    _logger.LogError(ex, "Помилка при створенні контрагента {CounterpartyName}", counterparty.Name);
                    ModelState.AddModelError("", "Не вдалося створити контрагента.");
                    if (ex.InnerException is Npgsql.PostgresException pgEx && pgEx.SqlState == PostgresErrorCodes.UniqueViolation) { /* ... обробка ... */ }
                }
            }

            var allRoles = await _context.CounterpartyRoles.OrderBy(r => r.Name).ToListAsync();
            model.RolesCheckboxes = allRoles.Select(r => new RoleCheckboxViewModel
            {
                Id = r.RoleId,
                Name = r.Name,
                IsAssigned = model.SelectedRoleIds?.Contains(r.RoleId) ?? false
            }).ToList();

            ViewData["Title"] = "Створити контрагента (Помилка)";
            return View(model);
        }

        // GET: Counterparties/Edit/НазваКонтрагента
        [HttpGet("Edit/{name}")]
        public async Task<IActionResult> Edit(string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                return BadRequest("Не вказано назву контрагента.");
            }

            var counterparty = await _context.Counterparties
                                      .Include(c => c.Roles)
                                      .FirstOrDefaultAsync(c => c.Name == name);

            if (counterparty == null) return NotFound();

            var allRoles = await _context.CounterpartyRoles
                                         .OrderBy(r => r.Name)
                                         .ToListAsync();

            var viewModel = new CounterpartyViewModel
            {
                OriginalName = counterparty.Name, 
                Name = counterparty.Name,
                PhoneNumber = counterparty.PhoneNumber,
                Email = counterparty.Email,
                RolesCheckboxes = allRoles.Select(role => new RoleCheckboxViewModel
                {
                    Id = role.RoleId,
                    Name = role.Name,
                    IsAssigned = counterparty.Roles.Any(assignedRole => assignedRole.RoleId == role.RoleId)
                }).ToList()
            };

            ViewData["Title"] = $"Редагувати: {counterparty.Name}";
            return View(viewModel);
        }

        // POST: Counterparties/Edit/СтараНазва
        [HttpPost("Edit/{originalName}")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit([FromRoute] string originalName, CounterpartyViewModel model)
        {
            if (string.IsNullOrEmpty(originalName)) return BadRequest("Original counterparty name not provided.");

            if (model == null) return BadRequest("Form data missing.");

            model.OriginalName = originalName;

            if (originalName != model.Name && await CounterpartyExists(model.Name))
            {
                ModelState.AddModelError("Name", $"Контрагент з назвою '{model.Name}' вже існує.");
            }

            ModelState.Remove(nameof(CounterpartyViewModel.RolesCheckboxes));

            if (ModelState.IsValid)
            {
                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    int affectedRows = 0;
                    bool nameChanged = originalName != model.Name;

                    if (nameChanged)
                    {
                        string sql = @"UPDATE public.counterparty
                                  SET name = {0}, phone_number = {1}, email = {2}
                                  WHERE name = {3}";
                        affectedRows = await _context.Database.ExecuteSqlRawAsync(sql,
                            model.Name, model.PhoneNumber, model.Email, originalName);
                    }
                    else
                    {
                        var entityToUpdate = await _context.Counterparties.FindAsync(originalName);
                        if (entityToUpdate != null)
                        {
                            entityToUpdate.PhoneNumber = model.PhoneNumber;
                            entityToUpdate.Email = model.Email;
                            _context.Counterparties.Update(entityToUpdate);
                            affectedRows = await _context.SaveChangesAsync();
                            affectedRows = 1; 
                        }
                    }

                    if (affectedRows == 0)
                    {
                        await transaction.RollbackAsync();
                        _logger.LogWarning("Спроба оновлення неіснуючого контрагента (ориг. назва {OriginalName})", originalName);
                        TempData["ErrorMessage"] = "Контрагент, якого ви намагаєтесь редагувати, не знайдено.";
                        return RedirectToAction(nameof(Index));
                    }

                    var counterpartyToUpdateRoles = await _context.Counterparties
                                                                 .Include(c => c.Roles)
                                                                 .FirstOrDefaultAsync(c => c.Name == model.Name);

                    if (counterpartyToUpdateRoles != null)
                    {
                        var selectedRoleIds = new HashSet<int>(model.SelectedRoleIds ?? new List<int>());
                        var currentRoleIds = counterpartyToUpdateRoles.Roles.Select(r => r.RoleId).ToHashSet();

                        var rolesToRemove = counterpartyToUpdateRoles.Roles
                                              .Where(r => !selectedRoleIds.Contains(r.RoleId))
                                              .ToList();
                        foreach (var roleToRemove in rolesToRemove)
                        {
                            counterpartyToUpdateRoles.Roles.Remove(roleToRemove);
                        }

                        var roleIdsToAdd = selectedRoleIds.Where(id => !currentRoleIds.Contains(id)).ToList();
                        if (roleIdsToAdd.Any())
                        {
                            var rolesToAdd = await _context.CounterpartyRoles
                                                           .Where(r => roleIdsToAdd.Contains(r.RoleId))
                                                           .ToListAsync();
                            foreach (var roleToAdd in rolesToAdd)
                            {
                                counterpartyToUpdateRoles.Roles.Add(roleToAdd);
                            }
                        }

                        await _context.SaveChangesAsync();
                    }
                    else
                    {
                        _logger.LogError("Не вдалося знайти контрагента {CounterpartyName} після оновлення базових даних для оновлення ролей.", model.Name);
                        throw new Exception("Помилка синхронізації даних після оновлення.");
                    }

                    await transaction.CommitAsync();
                    TempData["SuccessMessage"] = $"Контрагента '{model.Name}' успішно оновлено.";
                    return RedirectToAction(nameof(Index));
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Помилка при оновленні контрагента (ориг. назва {OriginalName})", originalName);
                    ModelState.AddModelError("", "Не вдалося оновити контрагента.");
                }
            }

            var allRoles = await _context.CounterpartyRoles.OrderBy(r => r.Name).ToListAsync();
            model.RolesCheckboxes = allRoles.Select(r => new RoleCheckboxViewModel
            {
                Id = r.RoleId,
                Name = r.Name,
                IsAssigned = model.SelectedRoleIds?.Contains(r.RoleId) ?? false
            }).ToList();

            ViewData["Title"] = $"Редагувати: {originalName} (Помилка)";
            return View(model);
        }

        // GET: Counterparties/Delete/НазваКонтрагента
        [HttpGet("Delete/{name}")]
        public async Task<IActionResult> Delete(string name)
        {
            if (string.IsNullOrEmpty(name)) return NotFound();

            ViewData["Title"] = $"Видалити контрагента: {name}";
            var counterparty = await _context.Counterparties
                                      .Include(c => c.Roles)
                                      .FirstOrDefaultAsync(c => c.Name == name); 
            if (counterparty == null)
            {
                _logger.LogWarning("Спроба видалення неіснуючого контрагента: {CounterpartyName}", name);
                TempData["ErrorMessage"] = $"Контрагента з назвою '{name}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            bool hasInvoices = await _context.Invoices.AnyAsync(i => i.CounterpartyName == name);

            ViewBag.CanDelete = !(hasInvoices);
            string warnings = "";
            if (hasInvoices) warnings += "Контрагент фігурує в накладних. ";
            ViewBag.WarningMessage = string.IsNullOrEmpty(warnings) ? null : $"Неможливо видалити: {warnings.Trim()}";

            return View(counterparty);
        }

        // POST: Counterparties/Delete/НазваКонтрагента
        [HttpPost("Delete/{name}"), ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(string name)
        {
            if (string.IsNullOrEmpty(name)) return NotFound();

            bool hasInvoices = await _context.Invoices.AnyAsync(i => i.CounterpartyName == name);

            if (hasInvoices)
            {
                _logger.LogWarning("Спроба видалення контрагента '{CounterpartyName}', що має залежності.", name);
                string errorMsg = "Неможливо видалити контрагента, оскільки ";
                errorMsg += "він фігурує в накладних; ";
                TempData["ErrorMessage"] = errorMsg.Trim();
                return RedirectToAction(nameof(Index));
            }

            var counterparty = await _context.Counterparties.FindAsync(name);
            if (counterparty != null)
            {
                try
                {
                    _context.Counterparties.Remove(counterparty);
                    await _context.SaveChangesAsync();
                    TempData["SuccessMessage"] = $"Контрагента '{name}' успішно видалено.";
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при видаленні контрагента {CounterpartyName}", name);
                    TempData["ErrorMessage"] = "Не вдалося видалити контрагента.";
                }
            }
            else
            {
                TempData["ErrorMessage"] = $"Контрагента '{name}' не знайдено.";
            }
            return RedirectToAction(nameof(Index));
        }

        // GET: Counterparties/Details/НазваКонтрагента
        [HttpGet("Details/{name}")]
        public async Task<IActionResult> Details(string name)
        {
            if (string.IsNullOrEmpty(name)) return BadRequest();

            ViewData["Title"] = $"Деталі: {name}";

            try
            {
                var counterparty = await _context.Counterparties
                                                .Include(c => c.Roles)
                                                .Include(c => c.Invoices)
                                                    .ThenInclude(i => i.ListEntries)
                                                .AsNoTracking()
                                                .FirstOrDefaultAsync(c => c.Name == name);

                if (counterparty == null)
                {
                    _logger.LogWarning("Спроба перегляду деталей неіснуючого контрагента: {CounterpartyName}", name);
                    TempData["ErrorMessage"] = $"Контрагента з назвою '{name}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                var viewModel = new CounterpartyDetailsViewModel
                {
                    Counterparty = counterparty,
                    IsSupplier = counterparty.Roles.Any(r => r.Name?.ToLowerInvariant() == "supplier"),
                    IsCustomer = counterparty.Roles.Any(r => r.Name?.ToLowerInvariant() == "customer")
                };

                if (viewModel.IsSupplier)
                {
                    var suppliedProductNames = counterparty.Invoices
                        .Where(i => i.Type == InvoiceType.supply)
                        .SelectMany(i => i.ListEntries)
                        .Select(le => le.ProductName)
                        .Distinct()
                        .ToList();

                    if (suppliedProductNames.Any())
                    {
                        viewModel.SuppliedProducts = await _context.Products
                            .Include(p => p.UnitCodeNavigation)
                            .Where(p => suppliedProductNames.Contains(p.ProductName))
                            .OrderBy(p => p.ProductName)
                            .ToListAsync();
                    }
                }
                if (viewModel.IsCustomer)
                {
                    var purchasedProductNames = counterparty.Invoices
                        .Where(i => i.Type == InvoiceType.release)
                        .SelectMany(i => i.ListEntries)
                        .Select(le => le.ProductName)
                        .Distinct()
                        .ToList();

                    if (purchasedProductNames.Any())
                    {
                        viewModel.PurchasedProducts = await _context.Products
                           .Include(p => p.UnitCodeNavigation)
                           .Where(p => purchasedProductNames.Contains(p.ProductName))
                           .OrderBy(p => p.ProductName)
                           .ToListAsync();
                    }
                }
            
                return View(viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей контрагента {CounterpartyName}", name);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталі контрагента.";
                return RedirectToAction(nameof(Index));
            }
        }

        private async Task<bool> CounterpartyExists(string name)
        {
            return await _context.Counterparties.AnyAsync(e => e.Name == name);
        }
    }
}