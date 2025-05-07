using IMS.Models;
using X.PagedList;

namespace IMS.ViewModels
{
    public class CounterpartyDetailsViewModel
    {
        public Counterparty Counterparty { get; set; } 
        public IPagedList<Invoice>? RelatedInvoices { get; set; }
        public IPagedList<Product>? SuppliedProducts { get; set; } 
        public IPagedList<Product>? PurchasedProducts { get; set; }

        public int CurrentInvoicesPage { get; set; }
        public int CurrentSuppliedProductsPage { get; set; }
        public int CurrentPurchasedProductsPage { get; set; }
        public bool IsSupplier { get; set; }
        public bool IsCustomer { get; set; }
    }
}