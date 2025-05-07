using IMS.Models;
using X.PagedList;

namespace IMS.ViewModels
{
    public class StorageKeeperDetailsViewModel
    {
        public StorageKeeper Keeper { get; set; } 

        public IPagedList<Invoice>? RelatedInvoices { get; set; } 

        public int CurrentInvoicesPage { get; set; }

        public bool FromStorage { get; set; }
    }
}
