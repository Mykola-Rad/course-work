using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class InvoiceListEntryViewModel
    {
        [Required(ErrorMessage = "Please select a product.")]
        [Display(Name = "Product")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Unit")]
        public string? UnitName { get; set; }

        [Required(ErrorMessage = "Please enter the quantity.")]
        [Range(0.01, 99999999.99, ErrorMessage = "Quantity must be greater than zero.")]
        [Display(Name = "Quantity")]
        public decimal Count { get; set; }

        [Range(0, 99999999.99, ErrorMessage = "Price must be non-negative.")]
        [Display(Name = "Price per Unit")]
        public decimal Price { get; set; } = 0;

        [Display(Name = "Total")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal LineTotal => Count * Price;

        public bool IsMarkedForDeletion { get; set; } = false;
        public int TempId { get; set; }
    }
}