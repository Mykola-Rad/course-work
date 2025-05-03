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

        [Required(ErrorMessage = "Вкажіть кількість.")]
        [Range(0, 99999999.99, ErrorMessage = "Кількість має бути невід'ємною.")]
        [Display(Name = "Поточна кількість")]
        public decimal Count { get; set; }

        [Required(ErrorMessage = "Вкажіть мінімальний залишок.")]
        [Range(0, 99999999.99, ErrorMessage = "Мінімальний залишок має бути невід'ємним.")]
        [Display(Name = "Мінімальний залишок")]
        public decimal MinimalCount { get; set; }
    }
}