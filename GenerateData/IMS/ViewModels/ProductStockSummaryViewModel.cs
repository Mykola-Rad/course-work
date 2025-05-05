using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class ProductStockSummaryViewModel
    {
        [Display(Name = "Назва товару")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Одиниця виміру")]
        public string? ProductUnitName { get; set; } 

        [Display(Name = "Загальна кількість")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal TotalCount { get; set; }

        [Display(Name = "Мінімальний залишок")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal TotalMinimal { get; set; }
    }
}
