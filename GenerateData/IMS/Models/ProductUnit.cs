using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class ProductUnit
{
    [Key]
    [Required]
    [StringLength(10)]
    public string UnitCode { get; set; } = null!;

    [Required]
    [StringLength(50)]
    public string UnitName { get; set; } = null!;

    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
}
