using System;
using System.Collections.Generic;

namespace GenerateData.Models;

public partial class Counterparty
{
    public string PhoneNumber { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? Email { get; set; }

    public virtual ICollection<Invoice> Invoices { get; set; } = new List<Invoice>();
}
