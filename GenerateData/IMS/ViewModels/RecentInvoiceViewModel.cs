using IMS.Models;

namespace IMS.ViewModels
{
    public class RecentInvoiceViewModel
    {
        public int InvoiceId { get; set; }
        public string DisplayInfo { get; set; } 
        public InvoiceStatus Status { get; set; }
    }
}
