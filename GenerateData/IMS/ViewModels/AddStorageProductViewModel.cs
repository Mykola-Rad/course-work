using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.ViewModels
{
    public class AddStorageProductViewModel : IValidatableObject
    {
        public string? PreSelectedStorageName { get; set; }

        [Display(Name = "Storage")]
        public string? SelectedStorageName { get; set; }

        [Required(ErrorMessage = "Product selection is required.")]
        [Display(Name = "Product")]
        public string SelectedProductName { get; set; } = null!;

        [Required(ErrorMessage = "Please enter the quantity.")]
        [Range(0, 99999999.99, ErrorMessage = "Quantity must be non-negative.")]
        [Display(Name = "Initial Quantity")]
        public decimal Count { get; set; } = 0;

        [Required(ErrorMessage = "Please enter the minimal stock level.")]
        [Range(0, 99999999.99, ErrorMessage = "Minimal stock level must be non-negative.")]
        [Display(Name = "Minimal Stock Level")]
        public decimal MinimalCount { get; set; } = 0;

        public SelectList? AvailableStorages { get; set; }
        public SelectList? AvailableProducts { get; set; }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            if (string.IsNullOrEmpty(PreSelectedStorageName) && string.IsNullOrEmpty(SelectedStorageName))
            {
                yield return new ValidationResult(
                    "Storage selection is required.",
                    new[] { nameof(SelectedStorageName) }
                );
            }
        }
    }
}