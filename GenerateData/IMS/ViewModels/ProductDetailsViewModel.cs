using IMS.Models;
using X.PagedList;

namespace IMS.ViewModels
{
    public class ProductDetailsViewModel
    {
        public Product Product { get; set; } 

        public IPagedList<Counterparty>? Customers { get; set; }
        public IPagedList<Counterparty>? Suppliers { get; set; } 

        public int CurrentCustomersPage { get; set; }
        public int CurrentSuppliersPage { get; set; }
    }
}
