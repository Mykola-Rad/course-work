using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using IMS.Data;
using IMS.Models;
using IMS.ViewModels;
using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;
using System.Text.Json;
using System.Text;

namespace IMS.Controllers
{
    [Authorize]
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;
        private readonly AppDbContext _context;

        public HomeController(ILogger<HomeController> logger, AppDbContext context)
        {
            _logger = logger;
            _context = context;
        }
        public async Task<IActionResult> Index()
        {
            var viewModel = new HomeIndexViewModel();

            if (User.Identity != null && User.Identity.IsAuthenticated &&
                (User.IsInRole(UserRole.manager.ToString()) || User.IsInRole(UserRole.owner.ToString())))
            {
                viewModel.ShowDashboard = true;
                viewModel.DashboardData = new DashboardViewModel();

                try
                {
                    var today = DateOnly.FromDateTime(DateTime.Today);
                    var startOfMonth = new DateOnly(today.Year, today.Month, 1);
                    var endOfMonth = startOfMonth.AddMonths(1).AddDays(-1);

                    var monthlySums = await _context.Invoices
                        .Where(i => i.Status == InvoiceStatus.processed &&
                                    i.Date >= startOfMonth && i.Date <= endOfMonth)
                        .SelectMany(i => i.ListEntries.Select(le => new { i.Type, Amount = le.Count * le.Price }))
                        .GroupBy(x => x.Type)
                        .Select(g => new { Type = g.Key, Total = g.Sum(x => x.Amount) })
                        .ToListAsync();

                    viewModel.DashboardData.InvoiceSummary.SupplySumCurrentMonth = monthlySums.FirstOrDefault(s => s.Type == InvoiceType.supply)?.Total ?? 0m;
                    viewModel.DashboardData.InvoiceSummary.ReleaseSumCurrentMonth = monthlySums.FirstOrDefault(s => s.Type == InvoiceType.release)?.Total ?? 0m;

                    viewModel.DashboardData.InvoiceSummary.DraftInvoiceCount = await _context.Invoices.Where(i => i.Date >= startOfMonth && i.Date <= endOfMonth)
                                                                                .CountAsync(i => i.Status == InvoiceStatus.draft);


                    viewModel.DashboardData.LowStockInfo.LowStockItemsCount = await _context.StorageProducts
                                                                        .CountAsync(sp => sp.MinimalCount > 0 && sp.Count <= sp.MinimalCount);

                    viewModel.DashboardData.RecentInvoices = await _context.Invoices
                        .OrderByDescending(i => i.Date).ThenByDescending(i => i.InvoiceId)
                        .Take(5)
                        .Select(i => new RecentInvoiceViewModel
                        {
                            InvoiceId = i.InvoiceId,
                            DisplayInfo = $"№{i.InvoiceId} - {i.Type.ToString()} - {i.Date.ToString("dd.MM.yyyy")}",
                            Status = i.Status
                        })
                        .ToListAsync();

                    var startDateForTopMovers = today.AddDays(-29);

                    viewModel.DashboardData.TopMovingProducts = await _context.ListEntries
    .AsNoTracking()
    .Where(le => le.Invoice.Status == InvoiceStatus.processed &&
                 le.Invoice.Type == InvoiceType.release &&
                 le.Invoice.Date >= startDateForTopMovers && le.Invoice.Date <= today)
    .GroupBy(le => le.ProductName)
    .Select(g => new TopMovingProductViewModel
    {
        ProductName = g.Key,
        TotalSoldValue = g.Sum(le => le.Count * le.Price)
    })
    .OrderByDescending(p => p.TotalSoldValue)
    .Take(5)
    .ToListAsync();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Помилка при завантаженні даних для Дашборду в HomeController");
                    TempData["WarningMessage"] = "Не вдалося завантажити дані дашборду.";
                }
            }
            else
            {
                viewModel.ShowDashboard = false;
            }

            return View(viewModel);
        }

        [HttpGet("ExportInvoicesJson")]
        [Authorize(Roles = nameof(UserRole.manager) + "," + nameof(UserRole.owner))]
        public async Task<IActionResult> ExportInvoicesJson(DateOnly? dateFrom, DateOnly? dateTo)
        {
            if (!dateFrom.HasValue || !dateTo.HasValue || dateFrom > dateTo)
            {
                TempData["ErrorMessage"] = "Будь ласка, оберіть коректний період.";
                return RedirectToAction(nameof(Index));
            }
            try
            {
                var invoicesToExport = await _context.Invoices
                    .AsNoTracking()
                    .Include(i => i.ListEntries)
                        .ThenInclude(le => le.ProductNameNavigation.UnitCodeNavigation)
                    .Where(i =>
                        i.Status == InvoiceStatus.processed &&
                        i.Date >= dateFrom.Value &&
                        i.Date <= dateTo.Value)
                    .OrderBy(i => i.Date).ThenBy(i => i.InvoiceId)
                    .ToListAsync();

                if (!invoicesToExport.Any()) { TempData["InfoMessage"] = "Немає проведених накладних для експорту за обраний період."; return RedirectToAction(nameof(Index)); }

                var exportData = invoicesToExport.Select(i => new InvoiceExportDto
                {
                    InvoiceId = i.InvoiceId,
                    Date = i.Date,
                    Type = i.Type.ToString(),
                    Status = i.Status.ToString(),
                    CounterpartyName = i.CounterpartyName,
                    SenderStorageName = i.SenderStorageName,
                    ReceiverStorageName = i.ReceiverStorageName,
                    Items = i.ListEntries.Select(le => new ListEntryExportDto
                    {
                        ProductName = le.ProductName,
                        Count = le.Count,
                        UnitName = le.ProductNameNavigation?.UnitCodeNavigation?.UnitName ?? "N/A",
                        Price = le.Price,
                        ItemTotal = le.Count * le.Price
                    }).ToList(),
                    TotalAmount = i.ListEntries.Sum(le => le.Count * le.Price)
                }).ToList();

                var options = new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
                string jsonString = JsonSerializer.Serialize(exportData, options);
                var jsonBytes = Encoding.UTF8.GetBytes(jsonString);
                var fileName = $"ims_invoices_{dateFrom:yyyyMMdd}_{dateTo:yyyyMMdd}.json";
                return File(jsonBytes, "application/json", fileName);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Помилка при експорті накладних в JSON з HomeController");
                TempData["ErrorMessage"] = "Помилка під час експорту даних.";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpGet("LowStockItems")]
        [Authorize(Roles = nameof(UserRole.manager) + "," + nameof(UserRole.owner))]
        public IActionResult LowStockItems()
        {
            return RedirectToAction("Index", "StorageProduct", new { filterLowStock = true });
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        [AllowAnonymous]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
