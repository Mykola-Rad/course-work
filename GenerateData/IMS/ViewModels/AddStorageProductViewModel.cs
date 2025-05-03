using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.ViewModels
{
    public class AddStorageProductViewModel : IValidatableObject
    {
        public string? PreSelectedStorageName { get; set; }

        [Display(Name = "Склад")]
        public string? SelectedStorageName { get; set; } 

        [Required(ErrorMessage = "Необхідно обрати товар.")]
        [Display(Name = "Товар")]
        public string SelectedProductName { get; set; } = null!;

        [Required(ErrorMessage = "Вкажіть кількість.")]
        [Range(0, 99999999.99, ErrorMessage = "Кількість має бути невід'ємною.")]
        [Display(Name = "Початкова кількість")]
        public decimal Count { get; set; } = 0;

        [Required(ErrorMessage = "Вкажіть мінімальний залишок.")]
        [Range(0, 99999999.99, ErrorMessage = "Мінімальний залишок має бути невід'ємним.")]
        [Display(Name = "Мінімальний залишок")]
        public decimal MinimalCount { get; set; } = 0;

        public SelectList? AvailableStorages { get; set; }
        public SelectList? AvailableProducts { get; set; }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            if (string.IsNullOrEmpty(PreSelectedStorageName) && string.IsNullOrEmpty(SelectedStorageName))
            {
                yield return new ValidationResult(
                    "Необхідно обрати склад.", 
                    new[] { nameof(SelectedStorageName) } 
                );
            }
        }
    }
}