using System.ComponentModel.DataAnnotations;
using IMS.Models;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.ViewModels
{
    public class UserViewModel
    {
        public int UserId { get; set; }

        [Required(ErrorMessage = "Ім'я користувача є обов'язковим")]
        [Display(Name = "Ім'я користувача (логін)")]
        public string Username { get; set; }

        [Required(ErrorMessage = "Роль є обов'язковою")]
        [Display(Name = "Роль")]
        public UserRole Role { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Пароль (залиште порожнім, щоб не міняти)")]
        [StringLength(100, ErrorMessage = "{0} має бути принаймні {2} символів.", MinimumLength = 6)]
        public string? Password { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Підтвердження пароля")]
        [Compare("Password", ErrorMessage = "Пароль та підтвердження не співпадають.")]
        public string? ConfirmPassword { get; set; }


        [Display(Name = "Прив'язаний комірник")]
        public string? SelectedStorageKeeperPhoneNumber { get; set; }
        public IEnumerable<SelectListItem>? AvailableKeepers { get; set; }
    }
}