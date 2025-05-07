using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class EditMinimalCountViewModel
    {
        [Required]
        public string StorageName { get; set; } = null!;
        [Required]
        public string ProductName { get; set; } = null!;

        public string? ProductDisplayName { get; set; }

        [Required(ErrorMessage = "Please enter the minimal stock level.")]
        [Range(0.00, 99999999.99, ErrorMessage = "Minimal stock level must be non-negative.")]
        [Display(Name = "New Minimal Stock Level")]
        public decimal MinimalCount { get; set; }
    }
}