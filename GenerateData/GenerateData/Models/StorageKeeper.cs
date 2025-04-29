using System;
using System.Collections.Generic;

namespace GenerateData.Models;

public partial class StorageKeeper
{
    public string PhoneNumber { get; set; } = null!;

    public string StorageName { get; set; } = null!;

    public string? Username { get; set; }

    public string FirstName { get; set; } = null!;

    public string LastName { get; set; } = null!;

    public string? Email { get; set; }

    public virtual ICollection<Invoice> InvoiceReceiverKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual Storage StorageNameNavigation { get; set; } = null!;

    public virtual User? UsernameNavigation { get; set; }
}
