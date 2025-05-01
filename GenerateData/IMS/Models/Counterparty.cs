using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class Counterparty
{
    public string PhoneNumber { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? Email { get; set; }

    public virtual ICollection<Invoice> Invoices { get; set; } = new List<Invoice>();

    public virtual ICollection<CounterpartyRole> Roles { get; set; } = new List<CounterpartyRole>();
}
