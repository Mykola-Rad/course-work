using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class EditStorageProductViewModel
    {
        [Required]
        public string StorageName { get; set; } = null!;

        [Required]
        public string ProductName { get; set; } = null!;

        public string? ProductDisplayName { get; set; }
        public string? UnitName { get; set; }

        [Required(ErrorMessage = "Please enter the quantity.")]
        [Range(0, 99999999.99, ErrorMessage = "Quantity must be non-negative.")]
        [Display(Name = "Current Quantity")]
        public decimal Count { get; set; }

        [Required(ErrorMessage = "Please enter the minimal stock level.")]
        [Range(0, 99999999.99, ErrorMessage = "Minimal stock level must be non-negative.")]
        [Display(Name = "Minimal Stock Level")]
        public decimal MinimalCount { get; set; }

        [StringLength(500, ErrorMessage = "Reason cannot exceed 500 characters.")]
        [Display(Name = "Adjustment Reason (optional)")]
        public string? AdjustmentReason { get; set; }
    }
}