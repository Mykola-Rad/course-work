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

        [Required(ErrorMessage = "Вкажіть мінімальний залишок.")]
        [Range(0.00, 99999999.99, ErrorMessage = "Мінімальний залишок має бути невід'ємним.")]
        [Display(Name = "Новий Мінімальний залишок")]
        public decimal MinimalCount { get; set; }
    }
}
