using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class ProductUnit
{
    [Key]
    [Required(ErrorMessage = "Код одиниці виміру є обов'язковим.")]
    [StringLength(10, ErrorMessage = "Код одиниці виміру не може перевищувати 10 символів.")]
    [Display(Name = "Код одиниці")]
    public string UnitCode { get; set; } = null!;

    [Required(ErrorMessage = "Назва одиниці виміру є обов'язковою.")]
    [StringLength(50, ErrorMessage = "Назва одиниці виміру не може перевищувати 50 символів.")]
    [Display(Name = "Назва одиниці")]
    public string UnitName { get; set; } = null!;

    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
}
