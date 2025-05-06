using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class LoginViewModel
    {
        [Required(ErrorMessage = "Ім'я користувача є обов'язковим")]
        [Display(Name = "Ім'я користувача")]
        public string Username { get; set; }

        [Required(ErrorMessage = "Пароль є обов'язковим")]
        [DataType(DataType.Password)]
        [Display(Name = "Пароль")]
        public string Password { get; set; }

        [Display(Name = "Запам'ятати мене?")]
        public bool RememberMe { get; set; }
    }
}
