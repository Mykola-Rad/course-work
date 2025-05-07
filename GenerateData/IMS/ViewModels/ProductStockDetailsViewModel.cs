using IMS.Models;
using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class ProductStockDetailsViewModel
    {
        [Display(Name = "Product")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Unit of Measure")]
        public string? ProductUnitName { get; set; }

        public List<StorageProduct> StockDetails { get; set; } = new List<StorageProduct>();
    }
}