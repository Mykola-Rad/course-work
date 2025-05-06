using IMS.Models;
using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class ProductStockDetailsViewModel
    {
        [Display(Name = "Товар")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Одиниця виміру")]
        public string? ProductUnitName { get; set; } 

        public List<StorageProduct> StockDetails { get; set; } = new List<StorageProduct>();
    }
}
