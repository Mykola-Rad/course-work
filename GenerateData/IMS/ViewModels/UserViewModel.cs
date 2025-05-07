using System.ComponentModel.DataAnnotations;
using IMS.Models;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace IMS.ViewModels
{
    public class UserViewModel
    {
        public int UserId { get; set; }

        [Required(ErrorMessage = "Username is required")]
        [Display(Name = "Username (login)")]
        public string Username { get; set; }

        [Required(ErrorMessage = "Role is required")]
        [Display(Name = "Role")]
        public UserRole Role { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Password (leave empty to not change)")]
        [StringLength(100, ErrorMessage = "{0} must be at least {2} characters long.", MinimumLength = 6)]
        public string? Password { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Confirm Password")]
        [Compare("Password", ErrorMessage = "The password and confirmation password do not match.")]
        public string? ConfirmPassword { get; set; }


        [Display(Name = "Assigned Storage Keeper")]
        public string? SelectedStorageKeeperPhoneNumber { get; set; }
        public IEnumerable<SelectListItem>? AvailableKeepers { get; set; }
    }
}