namespace IMS.ViewModels
{
    public class DashboardViewModel
    {
        public InvoiceSummaryStatsViewModel InvoiceSummary { get; set; }
        public LowStockInfoViewModel LowStockInfo { get; set; }
        public List<RecentInvoiceViewModel> RecentInvoices { get; set; }
        public List<TopMovingProductViewModel> TopMovingProducts { get; set; }

        public DashboardViewModel()
        {
            InvoiceSummary = new InvoiceSummaryStatsViewModel();
            LowStockInfo = new LowStockInfoViewModel();
            RecentInvoices = new List<RecentInvoiceViewModel>();
            TopMovingProducts = new List<TopMovingProductViewModel>();
        }
    }
}
