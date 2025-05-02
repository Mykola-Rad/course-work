using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class Product
{
    public string ProductName { get; set; } = null!;

    public string UnitCode { get; set; } = null!;

    public decimal LastPrice { get; set; }

    public virtual ICollection<ListEntry> ListEntries { get; set; } = new List<ListEntry>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();

    public virtual ProductUnit UnitCodeNavigation { get; set; } = null!;
}
