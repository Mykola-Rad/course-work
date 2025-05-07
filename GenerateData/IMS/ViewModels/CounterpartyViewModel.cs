using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class CounterpartyViewModel
    {
        public string? OriginalName { get; set; }

        [Required(ErrorMessage = "Counterparty name is required.")]
        [StringLength(100, MinimumLength = 3, ErrorMessage = "Counterparty name must be between 3 and 100 characters.")]
        [Display(Name = "Counterparty Name")]
        public string Name { get; set; } = null!;

        [Required(ErrorMessage = "Phone number is required.")]
        [StringLength(13, MinimumLength = 10, ErrorMessage = "The phone number length (including '+') must be between 10 and 13 characters.")]
        [RegularExpression(@"^\+\d+$", ErrorMessage = "The phone number must start with '+' and contain only digits.")]
        [Display(Name = "Phone Number")]
        public string PhoneNumber { get; set; } = null!;

        [EmailAddress(ErrorMessage = "Invalid Email format.")]
        [StringLength(255)]
        [Display(Name = "Email")]
        public string? Email { get; set; }

        public List<RoleCheckboxViewModel> RolesCheckboxes { get; set; } = new List<RoleCheckboxViewModel>();

        public List<int>? SelectedRoleIds { get; set; } = new List<int>();
    }
}