using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class ProductUnit
{
    public string UnitCode { get; set; } = null!;

    public string UnitName { get; set; } = null!;

    public virtual ICollection<Product> Products { get; set; } = new List<Product>();
}
