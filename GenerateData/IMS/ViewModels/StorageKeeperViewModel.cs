using Microsoft.AspNetCore.Mvc.Rendering;
using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class StorageKeeperViewModel
    {
        [Required(ErrorMessage = "Номер телефону є обов'язковим.")]
        [StringLength(13, MinimumLength = 10, ErrorMessage = "Довжина номера телефону (з '+') має бути від 10 до 13 символів.")]
        [RegularExpression(@"^\+\d+$", ErrorMessage = "Номер телефону має починатися зі знаку '+' і містити тільки цифри.")]
        [Display(Name = "Номер телефону (Ключ)")]
        public string PhoneNumber { get; set; } = null!;

        [Required(ErrorMessage = "Ім'я є обов'язковим.")]
        [StringLength(50)]
        [Display(Name = "Ім'я")]
        public string FirstName { get; set; } = null!;

        [Required(ErrorMessage = "Прізвище є обов'язковим.")]
        [StringLength(50)]
        [Display(Name = "Прізвище")]
        public string LastName { get; set; } = null!;

        [EmailAddress(ErrorMessage = "Неправильний формат Email.")]
        [StringLength(255)]
        [Display(Name = "Email")]
        public string? Email { get; set; }

        [Required(ErrorMessage = "Необхідно призначити склад.")]
        [Display(Name = "Призначений склад")]
        public string StorageName { get; set; } = null!;
        public string? OriginalPhoneNumber { get; set; } 
        public bool IsEditMode => !string.IsNullOrEmpty(OriginalPhoneNumber); 

        public SelectList? AvailableStorages { get; set; }
    }
}
