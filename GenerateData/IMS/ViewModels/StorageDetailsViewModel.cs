using IMS.Models;

namespace IMS.ViewModels
{
    public class StorageDetailsViewModel
    {
        public Storage Storage { get; set; } = null!;

        public List<Invoice> RelatedInvoices { get; set; } = new List<Invoice>();
    }
}
