namespace IMS.ViewModels
{
    public class InvoiceSummaryStatsViewModel
    {
        public decimal SupplySumCurrentMonth { get; set; }
        public decimal ReleaseSumCurrentMonth { get; set; }
        public int DraftInvoiceCount { get; set; }
    }
}
