using Microsoft.AspNetCore.Mvc.Rendering;
using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class StorageKeeperViewModel
    {
        [Required(ErrorMessage = "Phone number is required.")]
        [StringLength(13, MinimumLength = 10, ErrorMessage = "The phone number length (including '+') must be between 10 and 13 characters.")]
        [RegularExpression(@"^\+\d+$", ErrorMessage = "The phone number must start with '+' and contain only digits.")]
        [Display(Name = "Phone Number (Key)")]
        public string PhoneNumber { get; set; } = null!;

        [Required(ErrorMessage = "First name is required.")]
        [StringLength(50)]
        [Display(Name = "First Name")]
        public string FirstName { get; set; } = null!;

        [Required(ErrorMessage = "Last name is required.")]
        [StringLength(50)]
        [Display(Name = "Last Name")]
        public string LastName { get; set; } = null!;

        [EmailAddress(ErrorMessage = "Invalid Email format.")]
        [StringLength(255)]
        [Display(Name = "Email")]
        public string? Email { get; set; }

        [Required(ErrorMessage = "Storage assignment is required.")]
        [Display(Name = "Assigned Storage")]
        public string StorageName { get; set; } = null!;
        public string? OriginalPhoneNumber { get; set; }
        public bool IsEditMode => !string.IsNullOrEmpty(OriginalPhoneNumber);

        public SelectList? AvailableStorages { get; set; }
    }
}