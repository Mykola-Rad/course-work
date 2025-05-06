using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class CounterpartyViewModel
    {
        public string? OriginalName { get; set; }

        [Required(ErrorMessage = "Назва контрагента є обов'язковою.")]
        [StringLength(100, MinimumLength = 3, ErrorMessage = "Назва контрагента має бути від 3 до 100 символів.")]
        [Display(Name = "Назва контрагента")]
        public string Name { get; set; } = null!;

        [Required(ErrorMessage = "Номер телефону є обов'язковим.")]
        [StringLength(13, MinimumLength = 10, ErrorMessage = "Довжина номера телефону (з '+') має бути від 10 до 13 символів.")]
        [RegularExpression(@"^\+\d+$", ErrorMessage = "Номер телефону має починатися зі знаку '+' і містити тільки цифри.")]
        [Display(Name = "Номер телефону")]
        public string PhoneNumber { get; set; } = null!;

        [EmailAddress(ErrorMessage = "Неправильний формат Email.")]
        [StringLength(255)]
        [Display(Name = "Email")]
        public string? Email { get; set; }

        public List<RoleCheckboxViewModel> RolesCheckboxes { get; set; } = new List<RoleCheckboxViewModel>();

        public List<int>? SelectedRoleIds { get; set; } = new List<int>();
    }
}
