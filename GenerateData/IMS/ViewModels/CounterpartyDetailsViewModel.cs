using IMS.Models;

namespace IMS.ViewModels
{
    public class CounterpartyDetailsViewModel
    {
        public Counterparty Counterparty { get; set; } = null!;
        public List<Product> SuppliedProducts { get; set; } = new List<Product>();
        public List<Product> PurchasedProducts { get; set; } = new List<Product>();

        public bool IsSupplier { get; set; }
        public bool IsCustomer { get; set; }
    }
}