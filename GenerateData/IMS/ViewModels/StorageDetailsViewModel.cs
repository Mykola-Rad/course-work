using IMS.Models;
using X.PagedList;

namespace IMS.ViewModels
{
    public class StorageDetailsViewModel
    {
        public Storage Storage { get; set; } = null!;

        public IPagedList<StorageProduct> StorageProducts { get; set; }
        public IPagedList<StorageKeeper> StorageKeepers { get; set; }
        public IPagedList<Invoice> RelatedInvoices { get; set; }

        public int CurrentProductsPage { get; set; }
        public int CurrentKeepersPage { get; set; }
        public int CurrentInvoicesPage { get; set; }
    }
}
