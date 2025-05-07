using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class ProductStockSummaryViewModel
    {
        [Display(Name = "Product Name")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Unit of Measure")]
        public string? ProductUnitName { get; set; }

        [Display(Name = "Total Quantity")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal TotalCount { get; set; }

        [Display(Name = "Total Minimal Stock")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal TotalMinimal { get; set; }
    }
}