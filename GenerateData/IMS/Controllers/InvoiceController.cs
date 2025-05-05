using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Data;
using IMS.Models;
using IMS.ViewModels;
using Microsoft.AspNetCore.Mvc.Rendering;
using Npgsql;
using X.PagedList.EF;
using X.PagedList;

namespace IMS.Controllers
{
    [Authorize(Policy = "RequireStorageKeeperRole")]
    [Route("Invoices")] 
    public class InvoiceController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<InvoiceController> _logger;
        private const int _pageSize = 10;

        public InvoiceController(AppDbContext context, ILogger<InvoiceController> logger) 
        {
            _context = context;
            _logger = logger;
        }

        // GET: Invoices
        [HttpGet("")]
        public async Task<IActionResult> Index(
            string? invoiceType = null,         
            InvoiceStatus? filterStatus = null,
            DateOnly? filterDateFrom = null,
            DateOnly? filterDateTo = null,
            string? filterCounterpartyName = null, 
            string? filterSenderStorage = null,    
            string? filterReceiverStorage = null,  
            int page = 1)                       
        {
            ViewData["Title"] = "Накладні";

            ViewData["CurrentInvoiceType"] = invoiceType;
            ViewData["CurrentStatusFilter"] = filterStatus;
            ViewData["CurrentDateFromFilter"] = filterDateFrom?.ToString("yyyy-MM-dd");
            ViewData["CurrentDateToFilter"] = filterDateTo?.ToString("yyyy-MM-dd");
            ViewData["CurrentCounterpartyFilter"] = filterCounterpartyName;
            ViewData["CurrentSenderStorageFilter"] = filterSenderStorage;
            ViewData["CurrentReceiverStorageFilter"] = filterReceiverStorage;

            int pageNumber = page;

            try
            {
                var invoicesQuery = _context.Invoices
                    .Include(i => i.CounterpartyNameNavigation)
                    .Include(i => i.SenderStorageNameNavigation)
                    .Include(i => i.ReceiverStorageNameNavigation)
                    .AsNoTracking()
                    .AsQueryable();

                if (!string.IsNullOrEmpty(invoiceType) && Enum.TryParse<InvoiceType>(invoiceType, true, out var typeToFilter))
                {
                    invoicesQuery = invoicesQuery.Where(i => i.Type == typeToFilter);
                }
                if (filterStatus.HasValue)
                {
                    invoicesQuery = invoicesQuery.Where(i => i.Status == filterStatus.Value);
                }
                if (filterDateFrom.HasValue)
                {
                    invoicesQuery = invoicesQuery.Where(i => i.Date >= filterDateFrom.Value);
                }
                if (filterDateTo.HasValue)
                {
                    invoicesQuery = invoicesQuery.Where(i => i.Date <= filterDateTo.Value);
                }
                if (!string.IsNullOrEmpty(filterCounterpartyName))
                {
                    invoicesQuery = invoicesQuery.Where(i => i.CounterpartyName != null && i.CounterpartyName.ToLower().Contains(filterCounterpartyName.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterSenderStorage))
                {
                    invoicesQuery = invoicesQuery.Where(i => i.SenderStorageName != null && i.SenderStorageName.ToLower().Contains(filterSenderStorage.ToLower()));
                }
                if (!string.IsNullOrEmpty(filterReceiverStorage))
                {
                    invoicesQuery = invoicesQuery.Where(i => i.ReceiverStorageName != null && i.ReceiverStorageName.ToLower().Contains(filterReceiverStorage.ToLower()));
                }

                PopulateStatusFilterList(filterStatus);

                var sortedQuery = invoicesQuery
                    .OrderByDescending(i => i.Date)
                    .ThenByDescending(i => i.InvoiceId);

                var pagedInvoices = await sortedQuery.ToPagedListAsync(pageNumber, _pageSize);

                return View(pagedInvoices); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні списку накладних з фільтрами");
                TempData["ErrorMessage"] = "Не вдалося завантажити список накладних.";
                PopulateStatusFilterList(filterStatus); 
                var emptyPagedList = new PagedList<Invoice>(Enumerable.Empty<Invoice>(), pageNumber, _pageSize);
                return View(emptyPagedList);
            }
        }

        private void PopulateStatusFilterList(InvoiceStatus? filterStatus)
        {
            try
            {
                var statusList = Enum.GetValues(typeof(InvoiceStatus)).Cast<InvoiceStatus>()
                                  .Select(s => new SelectListItem { Value = s.ToString(), Text = s.ToString() }).ToList();
                ViewBag.StatusFilterList = new SelectList(statusList, "Value", "Text", filterStatus?.ToString());
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to populate Invoice Status filter list.");
                ViewBag.StatusFilterList = new SelectList(new List<SelectListItem>());
            }
        }

        [HttpGet("AutocompleteCounterpartyName")]
        public async Task<IActionResult> AutocompleteCounterpartyName(string term)
        {
            if (string.IsNullOrWhiteSpace(term) || term.Length < 2) return Json(Enumerable.Empty<string>());
            var lowerTerm = term.ToLower();
            try
            {
                var matches = await _context.Counterparties 
                    .Where(c => c.Name.ToLower().Contains(lowerTerm))
                    .OrderBy(c => c.Name)
                    .Select(c => c.Name)
                    .Take(10)
                    .ToListAsync();
                return Json(matches);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during counterparty name autocomplete for term {Term}", term);
                return Json(Enumerable.Empty<string>());
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


        // GET: Invoices/Details/5
        [HttpGet("Details/{id:int}")] 
        [Authorize(Policy = "RequireStorageKeeperRole")] 
        public async Task<IActionResult> Details(int id)
        {
            ViewData["Title"] = $"Накладна №{id}";

            try
            {
                var invoice = await _context.Invoices
                                    .AsNoTracking()
                                    .FirstOrDefaultAsync(i => i.InvoiceId == id);

                if (invoice == null)
                {
                    _logger.LogWarning("Спроба перегляду неіснуючої накладної: ID {InvoiceId}", id);
                    TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                if (!string.IsNullOrEmpty(invoice.CounterpartyName))
                {
                    invoice.CounterpartyNameNavigation = await _context.Counterparties.AsNoTracking().FirstOrDefaultAsync(c => c.Name == invoice.CounterpartyName);
                }
                if (!string.IsNullOrEmpty(invoice.SenderStorageName))
                {
                    invoice.SenderStorageNameNavigation = await _context.Storages.AsNoTracking().FirstOrDefaultAsync(s => s.Name == invoice.SenderStorageName);
                }
                if (!string.IsNullOrEmpty(invoice.ReceiverStorageName))
                {
                    invoice.ReceiverStorageNameNavigation = await _context.Storages.AsNoTracking().FirstOrDefaultAsync(s => s.Name == invoice.ReceiverStorageName);
                }
                if (!string.IsNullOrEmpty(invoice.SenderKeeperPhone))
                {
                    invoice.SenderKeeperPhoneNavigation = await _context.StorageKeepers.AsNoTracking().FirstOrDefaultAsync(sk => sk.PhoneNumber == invoice.SenderKeeperPhone);
                }
                if (!string.IsNullOrEmpty(invoice.ReceiverKeeperPhone))
                {
                    invoice.ReceiverKeeperPhoneNavigation = await _context.StorageKeepers.AsNoTracking().FirstOrDefaultAsync(sk => sk.PhoneNumber == invoice.ReceiverKeeperPhone);
                }

                invoice.ListEntries = await _context.ListEntries
                    .Where(le => le.InvoiceId == id) 
                    .Include(le => le.ProductNameNavigation)
                        .ThenInclude(p => p.UnitCodeNavigation)
                    .OrderBy(le => le.ProductNameNavigation.ProductName) 
                    .AsNoTracking()
                    .ToListAsync();

                decimal totalSum = 0;
                if (invoice.Type == InvoiceType.supply || invoice.Type == InvoiceType.release)
                {
                    totalSum = invoice.ListEntries?.Sum(le => le.Count * le.Price) ?? 0;
                }
                ViewBag.TotalSum = totalSum;

                return View(invoice);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні деталей накладної {InvoiceId}", id);
                TempData["ErrorMessage"] = "Не вдалося завантажити деталі накладної.";
                return RedirectToAction(nameof(Index));
            }
        }

        // GET: Invoices/Create
        // GET: Invoices/Create?counterpartyName=...&senderStorageName=...&receiverStorageName=...
        [HttpGet("Create")]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Create(string? counterpartyName = null, string? senderStorageName = null, string? receiverStorageName = null)
        {
            ViewData["Title"] = "Створення нової накладної";

            var viewModel = new InvoiceViewModel
            {
                Date = DateOnly.FromDateTime(DateTime.Today), 
                Status = InvoiceStatus.draft, 
                                              
                CounterpartyName = counterpartyName,
                SenderStorageName = senderStorageName,
                ReceiverStorageName = receiverStorageName
            };

            await PopulateInvoiceDropdowns(viewModel);

            if (!string.IsNullOrEmpty(senderStorageName) && !string.IsNullOrEmpty(receiverStorageName))
            {
                viewModel.Type = InvoiceType.transfer;
            }
            else if (!string.IsNullOrEmpty(senderStorageName))
            {
                viewModel.Type = InvoiceType.release;
            }
            else if (!string.IsNullOrEmpty(receiverStorageName))
            {
                viewModel.Type = InvoiceType.supply;
            }


            return View(viewModel);
        }

        // POST: Invoices/Create
        [HttpPost("Create")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Create(InvoiceViewModel model)
        {
            bool needsCounterparty = (model.Type == InvoiceType.supply || model.Type == InvoiceType.release);
            bool needsSenderStorage = (model.Type == InvoiceType.release || model.Type == InvoiceType.transfer);
            bool needsReceiverStorage = (model.Type == InvoiceType.supply || model.Type == InvoiceType.transfer);
            bool needsSenderKeeper = needsSenderStorage;
            bool needsReceiverKeeper = needsReceiverStorage;

            if (!needsCounterparty) ModelState.Remove(nameof(model.CounterpartyName));
            if (!needsSenderStorage) ModelState.Remove(nameof(model.SenderStorageName));
            if (!needsReceiverStorage) ModelState.Remove(nameof(model.ReceiverStorageName));
            if (!needsSenderKeeper) ModelState.Remove(nameof(model.SenderKeeperPhone));
            if (!needsReceiverKeeper) ModelState.Remove(nameof(model.ReceiverKeeperPhone));
            ModelState.Remove(nameof(model.AvailableTypes));
            ModelState.Remove(nameof(model.AvailableCounterparties));
            ModelState.Remove(nameof(model.AvailableStorages));
            ModelState.Remove(nameof(model.AvailableKeepers));
            ModelState.Remove(nameof(model.AvailableProducts));

            if (model.ListEntries == null || !model.ListEntries.Any(le => !le.IsMarkedForDeletion)) 
            {
                ModelState.AddModelError("ListEntries", "Накладна має містити хоча б одну товарну позицію.");
                ModelState.AddModelError("", "Додайте хоча б один товар до накладної.");
            }
            else
            {
                if (model.Type == InvoiceType.supply || model.Type == InvoiceType.release)
                {
                    bool priceError = false;
                    foreach (var entry in model.ListEntries.Where(le => !le.IsMarkedForDeletion))
                    {
                        if (entry.Price <= 0)
                        {
                            priceError = true;
                        }
                    }
                    if (priceError)
                    {
                        ModelState.AddModelError("ListEntries", "Ціна для всіх товарів у накладних типу 'Постачання' або 'Видача' має бути більше нуля.");
                        ModelState.AddModelError("", "Ціна для всіх товарів має бути більше нуля.");
                    }
                }
                var duplicateProducts = model.ListEntries
                                              .Where(le => !le.IsMarkedForDeletion)
                                              .GroupBy(le => le.ProductName)
                                              .Where(g => g.Count() > 1)
                                              .Select(g => g.Key)
                                              .ToList();
                if (duplicateProducts.Any())
                {
                    ModelState.AddModelError("ListEntries", $"Товари не повинні повторюватись у накладній: {string.Join(", ", duplicateProducts)}");
                    ModelState.AddModelError("", $"Товари не повинні повторюватись у накладній.");
                }

            }

            if (ModelState.IsValid)
            {
                var invoice = new Invoice
                {
                    Date = model.Date,
                    Type = model.Type,
                    Status = InvoiceStatus.draft,
                    CounterpartyName = needsCounterparty ? model.CounterpartyName : null,
                    SenderStorageName = needsSenderStorage ? model.SenderStorageName : null,
                    ReceiverStorageName = needsReceiverStorage ? model.ReceiverStorageName : null,
                    SenderKeeperPhone = needsSenderKeeper ? model.SenderKeeperPhone : null,
                    ReceiverKeeperPhone = needsReceiverKeeper ? model.ReceiverKeeperPhone : null
                };

                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    _context.Invoices.Add(invoice);
                    await _context.SaveChangesAsync(); 

                    foreach (var entryVM in model.ListEntries.Where(le => !le.IsMarkedForDeletion))
                    {
                        var listEntry = new ListEntry
                        {
                            InvoiceId = invoice.InvoiceId,
                            ProductName = entryVM.ProductName,
                            Count = entryVM.Count,
                            Price = (model.Type == InvoiceType.supply || model.Type == InvoiceType.release) ? entryVM.Price : 0 
                        };
                        _context.ListEntries.Add(listEntry);
                    }

                    await _context.SaveChangesAsync();

                    await transaction.CommitAsync();

                    TempData["SuccessMessage"] = $"Накладну №{invoice.InvoiceId} успішно створено зі статусом '{invoice.Status}'.";
                    return RedirectToAction(nameof(Details), new { id = invoice.InvoiceId }); 

                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Помилка при збереженні нової накладної");
                    ModelState.AddModelError("", "Не вдалося зберегти накладну. Перевірте дані та спробуйте ще раз.");
                }
            }

            _logger.LogWarning("Створення накладної не вдалося через помилки валідації або збереження.");
            await PopulateInvoiceDropdowns(model);
            ViewData["Title"] = "Створення нової накладної (Помилка)";
            return View(model); 
        }

        // GET: Invoices/Edit/5
        [HttpGet("Edit/{id:int}")]
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> Edit(int id)
        {
            ViewData["Title"] = $"Редагувати Накладну №{id}";

            try
            {
                var invoice = await _context.Invoices
                    .Include(i => i.ListEntries)
                        .ThenInclude(le => le.ProductNameNavigation) 
                            .ThenInclude(p => p.UnitCodeNavigation)
                    .FirstOrDefaultAsync(i => i.InvoiceId == id);

                if (invoice == null)
                {
                    TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                if (invoice.Status != InvoiceStatus.draft)
                {
                    TempData["ErrorMessage"] = $"Неможливо редагувати накладну №{id}, оскільки її статус '{invoice.Status}', а не '{InvoiceStatus.draft}'.";
                    return RedirectToAction(nameof(Details), new { id = id });
                }

                var viewModel = new InvoiceViewModel
                {
                    InvoiceId = invoice.InvoiceId,
                    Date = invoice.Date,
                    Type = invoice.Type,
                    Status = invoice.Status,
                    CounterpartyName = invoice.CounterpartyName,
                    SenderStorageName = invoice.SenderStorageName,
                    ReceiverStorageName = invoice.ReceiverStorageName,
                    SenderKeeperPhone = invoice.SenderKeeperPhone,
                    ReceiverKeeperPhone = invoice.ReceiverKeeperPhone,
                    ListEntries = invoice.ListEntries.Select(le => new InvoiceListEntryViewModel
                    {
                        ProductName = le.ProductName, 
                        UnitName = le.ProductNameNavigation?.UnitCodeNavigation?.UnitName,
                        Count = le.Count,
                        Price = le.Price,
                        IsMarkedForDeletion = false
                    }).OrderBy(le => le.ProductName).ToList()
                };

                await PopulateInvoiceDropdowns(viewModel);

                return View(viewModel); 
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при завантаженні накладної {InvoiceId} для редагування", id);
                TempData["ErrorMessage"] = "Не вдалося завантажити накладну для редагування.";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: Invoices/Edit/5
        [HttpPost("Edit/{id:int}")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> Edit(int id, InvoiceViewModel model) 
        {
            if (id != model.InvoiceId)
            {
                _logger.LogWarning("Невідповідність ID в маршруті ({RouteId}) та моделі ({ModelId}) при редагуванні накладної.", id, model.InvoiceId);
                return BadRequest("Невідповідність ідентифікатора накладної.");
            }
            if (model == null) return BadRequest("Form data missing.");

            bool needsCounterparty = (model.Type == InvoiceType.supply || model.Type == InvoiceType.release);
            bool needsSenderStorage = (model.Type == InvoiceType.release || model.Type == InvoiceType.transfer);
            bool needsReceiverStorage = (model.Type == InvoiceType.supply || model.Type == InvoiceType.transfer);
            bool needsSenderKeeper = needsSenderStorage;
            bool needsReceiverKeeper = needsReceiverStorage;
            bool needsPrice = needsCounterparty;

            if (!needsCounterparty) ModelState.Remove(nameof(model.CounterpartyName));
            if (!needsSenderStorage) ModelState.Remove(nameof(model.SenderStorageName));
            if (!needsReceiverStorage) ModelState.Remove(nameof(model.ReceiverStorageName));
            if (!needsSenderKeeper) ModelState.Remove(nameof(model.SenderKeeperPhone));
            if (!needsReceiverKeeper) ModelState.Remove(nameof(model.ReceiverKeeperPhone));
            ModelState.Remove(nameof(model.AvailableTypes));
            ModelState.Remove(nameof(model.AvailableCounterparties));
            ModelState.Remove(nameof(model.AvailableStorages));
            ModelState.Remove(nameof(model.AvailableKeepers));
            ModelState.Remove(nameof(model.AvailableProducts));
            ModelState.Remove(nameof(model.ListEntries)); 

            var validListEntriesFromForm = model.ListEntries?.Where(le => !le.IsMarkedForDeletion).ToList() ?? new List<InvoiceListEntryViewModel>();

            if (!validListEntriesFromForm.Any())
            {
                ModelState.AddModelError(nameof(model.ListEntries), "Накладна має містити хоча б одну товарну позицію.");
                ModelState.AddModelError("", "Додайте хоча б один товар до накладної.");
            }
            else
            {
                if (needsPrice && validListEntriesFromForm.Any(le => le.Price <= 0))
                {
                    ModelState.AddModelError(nameof(model.ListEntries), "Ціна для всіх товарів у накладних типу 'Постачання' або 'Видача' має бути більше нуля.");
                    ModelState.AddModelError("", "Ціна для товарів має бути позитивною.");
                }

                var duplicateProducts = validListEntriesFromForm.GroupBy(le => le.ProductName).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
                if (duplicateProducts.Any())
                {
                    ModelState.AddModelError(nameof(model.ListEntries), $"Товари не повинні повторюватись: {string.Join(", ", duplicateProducts)}");
                    ModelState.AddModelError("", $"Товари не повинні повторюватись.");
                }

                var productNamesFromForm = validListEntriesFromForm.Select(le => le.ProductName).Distinct().ToList();
                var existingProducts = await _context.Products.Where(p => productNamesFromForm.Contains(p.ProductName)).Select(p => p.ProductName).ToListAsync();
                var missingProducts = productNamesFromForm.Except(existingProducts).ToList();
                if (missingProducts.Any())
                {
                    ModelState.AddModelError(nameof(model.ListEntries), $"Товари не знайдено в довіднику: {string.Join(", ", missingProducts)}");
                    ModelState.AddModelError("", $"Один або декілька обраних товарів не знайдено.");
                }
            }
            if (needsCounterparty && !string.IsNullOrEmpty(model.CounterpartyName) && !await _context.Counterparties.AnyAsync(c => c.Name == model.CounterpartyName))
                ModelState.AddModelError("CounterpartyName", "Обраний контрагент не існує.");
            if (needsSenderStorage && !string.IsNullOrEmpty(model.SenderStorageName) && !await _context.Storages.AnyAsync(s => s.Name == model.SenderStorageName))
                ModelState.AddModelError("SenderStorageName", "Обраний склад-відправник не існує.");
            if (needsReceiverStorage && !string.IsNullOrEmpty(model.ReceiverStorageName) && !await _context.Storages.AnyAsync(s => s.Name == model.ReceiverStorageName))
                ModelState.AddModelError("ReceiverStorageName", "Обраний склад-одержувач не існує.");
            if (needsSenderKeeper && !string.IsNullOrEmpty(model.SenderKeeperPhone) && !await _context.StorageKeepers.AnyAsync(sk => sk.PhoneNumber == model.SenderKeeperPhone))
                ModelState.AddModelError("SenderKeeperPhone", "Обраний комірник-відправник не існує.");
            if (needsReceiverKeeper && !string.IsNullOrEmpty(model.ReceiverKeeperPhone) && !await _context.StorageKeepers.AnyAsync(sk => sk.PhoneNumber == model.ReceiverKeeperPhone))
                ModelState.AddModelError("ReceiverKeeperPhone", "Обраний комірник-одержувач не існує.");

            if (ModelState.IsValid)
            {
                var invoiceInDb = await _context.Invoices
                                                .Include(i => i.ListEntries) 
                                                .FirstOrDefaultAsync(i => i.InvoiceId == id);

                if (invoiceInDb == null) { return NotFound($"Накладну з ID {id} не знайдено."); }
                if (invoiceInDb.Status != InvoiceStatus.draft)
                {
                    TempData["ErrorMessage"] = $"Неможливо редагувати накладну №{id} зі статусом '{invoiceInDb.Status}'.";
                    return RedirectToAction(nameof(Details), new { id = id });
                }

                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    invoiceInDb.Date = model.Date;
                    invoiceInDb.Type = model.Type;
                    invoiceInDb.CounterpartyName = needsCounterparty ? model.CounterpartyName : null;
                    invoiceInDb.SenderStorageName = needsSenderStorage ? model.SenderStorageName : null;
                    invoiceInDb.ReceiverStorageName = needsReceiverStorage ? model.ReceiverStorageName : null;
                    invoiceInDb.SenderKeeperPhone = needsSenderKeeper ? model.SenderKeeperPhone : null;
                    invoiceInDb.ReceiverKeeperPhone = needsReceiverKeeper ? model.ReceiverKeeperPhone : null;

                    _context.Entry(invoiceInDb).State = EntityState.Modified;

                    var productNamesFromFormSet = validListEntriesFromForm
                                                .Select(vm => vm.ProductName)
                                                .ToHashSet();
                    var existingEntriesFromDb = invoiceInDb.ListEntries.ToList(); 

                    var entriesToRemove = existingEntriesFromDb
                                            .Where(dbEntry => !productNamesFromFormSet.Contains(dbEntry.ProductName))
                                            .ToList();
                    if (entriesToRemove.Any())
                    {
                        _context.ListEntries.RemoveRange(entriesToRemove);
                        _logger.LogInformation("Invoice {InvoiceId}: Removing ListEntries for products: {Products}", id, string.Join(", ", entriesToRemove.Select(e => e.ProductName)));
                    }

                    foreach (var entryVM in validListEntriesFromForm)
                    {
                        var existingEntry = existingEntriesFromDb
                                            .FirstOrDefault(dbEntry => dbEntry.ProductName == entryVM.ProductName);

                        if (existingEntry != null) 
                        {
                            if (existingEntry.Count != entryVM.Count || existingEntry.Price != (needsPrice ? entryVM.Price : 0))
                            {
                                existingEntry.Count = entryVM.Count;
                                existingEntry.Price = needsPrice ? entryVM.Price : 0;
                                _context.Entry(existingEntry).State = EntityState.Modified; 
                                _logger.LogInformation("Invoice {InvoiceId}: Updating ListEntry for product {Product}. New Count: {Count}, New Price: {Price}", id, existingEntry.ProductName, existingEntry.Count, existingEntry.Price);
                            }
                        }
                        else 
                        {
                            var newEntry = new ListEntry
                            {
                                InvoiceId = invoiceInDb.InvoiceId,
                                ProductName = entryVM.ProductName, 
                                Count = entryVM.Count,
                                Price = needsPrice ? entryVM.Price : 0
                            };
                            _context.ListEntries.Add(newEntry);
                            _logger.LogInformation("Invoice {InvoiceId}: Adding new ListEntry for product {Product}. Count: {Count}, Price: {Price}", id, newEntry.ProductName, newEntry.Count, newEntry.Price);
                        }
                    }

                    await _context.SaveChangesAsync();

                    await transaction.CommitAsync();

                    TempData["SuccessMessage"] = $"Накладну №{invoiceInDb.InvoiceId} успішно оновлено.";
                    return RedirectToAction(nameof(Details), new { id = invoiceInDb.InvoiceId });
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Помилка при оновленні накладної {InvoiceId}", id);
                    ModelState.AddModelError("", "Не вдалося оновити накладну. Виникла помилка бази даних.");
                }
            }
            else
            {
                _logger.LogWarning("Оновлення накладної {InvoiceId} не вдалося через помилки валідації. Помилок: {ErrorCount}", id, ModelState.ErrorCount);
            }

            await PopulateInvoiceDropdowns(model);
            ViewData["Title"] = $"Редагувати Накладну №{id} (Помилка)";
            return View(model);
        }

        // GET: Invoices/Delete/5
        [HttpGet("Delete/{id:int}")]
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> Delete(int id)
        {
            ViewData["Title"] = $"Видалення Накладної №{id}";
            try
            {
                var invoice = await _context.Invoices
                                            .AsNoTracking()
                                            .FirstOrDefaultAsync(i => i.InvoiceId == id);

                if (invoice == null)
                {
                    TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                if (invoice.Status != InvoiceStatus.draft)
                {
                    TempData["ErrorMessage"] = $"Неможливо видалити накладну №{id}, оскільки її статус '{invoice.Status}', а не '{InvoiceStatus.draft}'. Можливо, її варто Скасувати?";
                    return RedirectToAction(nameof(Details), new { id = id }); 
                }

                return View(invoice);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при отриманні накладної {InvoiceId} для видалення", id);
                TempData["ErrorMessage"] = "Не вдалося відкрити сторінку видалення накладної.";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: Invoices/Delete/5
        [HttpPost("Delete/{id:int}"), ActionName("Delete")] 
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                var invoiceToDelete = await _context.Invoices
                                                    .Include(i => i.ListEntries) 
                                                    .FirstOrDefaultAsync(i => i.InvoiceId == id);

                if (invoiceToDelete == null)
                {
                    TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                    return RedirectToAction(nameof(Index));
                }

                if (invoiceToDelete.Status != InvoiceStatus.draft)
                {
                    TempData["ErrorMessage"] = $"Неможливо видалити накладну №{id} зі статусом '{invoiceToDelete.Status}'. Видаляти можна тільки чернетки.";
                    return RedirectToAction(nameof(Details), new { id = id });
                }

                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    if (invoiceToDelete.ListEntries.Any())
                    {
                        _context.ListEntries.RemoveRange(invoiceToDelete.ListEntries);
                    }

                    _context.Invoices.Remove(invoiceToDelete);

                    await _context.SaveChangesAsync();

                    await transaction.CommitAsync(); 

                    TempData["SuccessMessage"] = $"Чернетку накладної №{id} успішно видалено.";
                    _logger.LogInformation("Invoice {InvoiceId} (Draft) deleted by user {User}", id, User.Identity?.Name ?? "Unknown");
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Помилка при видаленні накладної {InvoiceId}", id);
                    TempData["ErrorMessage"] = "Не вдалося видалити накладну.";
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при пошуку накладної {InvoiceId} для видалення", id);
                TempData["ErrorMessage"] = "Не вдалося знайти накладну для видалення.";
            }

            return RedirectToAction(nameof(Index));
        }

        // POST: Invoices/Confirm/5
        [HttpPost("Confirm/{id:int}")] 
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")] 
        public async Task<IActionResult> ConfirmInvoice(int id)
        {
            var invoice = await _context.Invoices.FindAsync(id);

            if (invoice == null)
            {
                TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            if (invoice.Status != InvoiceStatus.draft)
            {
                TempData["ErrorMessage"] = $"Неможливо підтвердити накладну №{id}, оскільки її статус '{invoice.Status}', а не '{InvoiceStatus.draft}'.";
                return RedirectToAction(nameof(Details), new { id = id });
            }

            try
            {
                invoice.Status = InvoiceStatus.processing;
                _context.Invoices.Update(invoice); 
                await _context.SaveChangesAsync(); 

                _logger.LogInformation("Invoice {InvoiceId} confirmed by user {User}", id, User.Identity?.Name ?? "Unknown");
                TempData["SuccessMessage"] = $"Накладну №{id} успішно підтверджено. Статус: {invoice.Status}.";
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка підтвердження накладної {InvoiceId}", id);
                TempData["ErrorMessage"] = "Не вдалося підтвердити накладну.";
            }

            return RedirectToAction(nameof(Details), new { id = id }); 
        }


        // POST: Invoices/Cancel/5
        [HttpPost("Cancel/{id:int}")] 
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireManagerRole")]
        public async Task<IActionResult> CancelInvoice(int id)
        {
            var invoice = await _context.Invoices.FindAsync(id);

            if (invoice == null)
            {
                TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            if (invoice.Status != InvoiceStatus.draft && invoice.Status != InvoiceStatus.processing)
            {
                TempData["ErrorMessage"] = $"Неможливо скасувати накладну №{id}, оскільки її статус '{invoice.Status}' (можна скасувати тільки '{InvoiceStatus.draft}' або '{InvoiceStatus.processing}').";
                return RedirectToAction(nameof(Details), new { id = id });
            }

            try
            {
                invoice.Status = InvoiceStatus.cancelled;
                _context.Invoices.Update(invoice);
                await _context.SaveChangesAsync();

                _logger.LogWarning("Invoice {InvoiceId} CANCELLED by user {User}. Previous status was {PreviousStatus}", id, User.Identity?.Name ?? "Unknown", invoice.Status); 
                TempData["SuccessMessage"] = $"Накладну №{id} успішно скасовано. Статус: {invoice.Status}.";
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка скасування накладної {InvoiceId}", id);
                TempData["ErrorMessage"] = "Не вдалося скасувати накладну.";
            }

            return RedirectToAction(nameof(Details), new { id = id });
        }

        // POST: Invoices/Complete/5
        [HttpPost("Complete/{id:int}")]
        [ValidateAntiForgeryToken]
        [Authorize(Policy = "RequireStorageKeeperRole")]
        public async Task<IActionResult> CompleteInvoice(int id)
        {
            var invoice = await _context.Invoices.FindAsync(id); 

            if (invoice == null)
            {
                TempData["ErrorMessage"] = $"Накладну з ID '{id}' не знайдено.";
                return RedirectToAction(nameof(Index));
            }

            try
            {
                await _context.Database.ExecuteSqlInterpolatedAsync($"SELECT public.process_invoice({id});");

                TempData["SuccessMessage"] = $"Накладну №{id} успішно завершено. Залишки оновлено.";
                _logger.LogInformation("Invoice {InvoiceId} completed via SP by user {User}", id, User.Identity?.Name ?? "System");

            }
            catch (PostgresException pgEx) 
            {
                _logger.LogError(pgEx, "PostgreSQL error completing invoice {InvoiceId} via SP. SQLState: {SqlState}. Message: {ErrorMessage}", id, pgEx.SqlState, pgEx.MessageText);
                TempData["ErrorMessage"] = $"Помилка завершення накладної №{id}: {pgEx.MessageText}";
            }
            catch (Exception ex) 
            {
                _logger.LogError(ex, "General error completing invoice {InvoiceId} via SP", id);
                TempData["ErrorMessage"] = "Не вдалося завершити накладну через системну помилку.";
            }

            return RedirectToAction(nameof(Details), new { id = id });
        }

        private async Task PopulateInvoiceDropdowns(InvoiceViewModel viewModel)
        {
            viewModel.AvailableTypes = new SelectList(Enum.GetValues(typeof(InvoiceType))
                                                       .Cast<InvoiceType>()
                                                       .Select(e => new { Value = e.ToString(), Text = e.ToString() }), 
                                                   "Value", "Text", viewModel.Type);

            var counterparties = await _context.Counterparties.OrderBy(c => c.Name).Select(c => new { c.Name }).ToListAsync();
            viewModel.AvailableCounterparties = new SelectList(counterparties, "Name", "Name", viewModel.CounterpartyName);

            var storages = await _context.Storages.OrderBy(s => s.Name).Select(s => new { s.Name }).ToListAsync();
            viewModel.AvailableStorages = new SelectList(storages, "Name", "Name"); 

            var keepers = await _context.StorageKeepers
                                        .OrderBy(k => k.LastName).ThenBy(k => k.FirstName)
                                        .Select(k => new { Value = k.PhoneNumber, Text = $"{k.LastName} {k.FirstName} ({k.PhoneNumber})" })
                                        .ToListAsync();
            viewModel.AvailableKeepers = new SelectList(keepers, "Value", "Text");

            var products = await _context.Products.OrderBy(p => p.ProductName).Select(p => new { p.ProductName }).ToListAsync();
            viewModel.AvailableProducts = new SelectList(products, "ProductName", "ProductName");
        }

    }
}