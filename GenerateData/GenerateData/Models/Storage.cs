using System;
using System.Collections.Generic;

namespace GenerateData.Models;

public partial class Storage
{
    public string Name { get; set; } = null!;

    public string StreetName { get; set; } = null!;

    public string HouseNumber { get; set; } = null!;

    public string City { get; set; } = null!;

    public string Region { get; set; } = null!;

    public string PostalCode { get; set; } = null!;

    public virtual ICollection<Invoice> InvoiceReceiverStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<StorageKeeper> StorageKeepers { get; set; } = new List<StorageKeeper>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();
}
