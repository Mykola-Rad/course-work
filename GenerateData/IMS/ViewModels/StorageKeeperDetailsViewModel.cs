using IMS.Models;

namespace IMS.ViewModels
{
    public class StorageKeeperDetailsViewModel
    {
        public StorageKeeper Keeper { get; set; } = null!;

        public List<Invoice> RelatedInvoices { get; set; } = new List<Invoice>();

        public bool ShowInvoices { get; set; }
    }
}
