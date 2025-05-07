using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class ProductUnit
{
    [Key]
    [Required(ErrorMessage = "Unit code is required.")]
    [StringLength(10, ErrorMessage = "Unit code cannot exceed 10 characters.")]
    [Display(Name = "Unit Code")]
    public string UnitCode { get; set; } = null!;

    [Required(ErrorMessage = "Unit name is required.")]
    [StringLength(50, ErrorMessage = "Unit name cannot exceed 50 characters.")]
    [Display(Name = "Unit Name")]
    public string UnitName { get; set; } = null!;

    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
}