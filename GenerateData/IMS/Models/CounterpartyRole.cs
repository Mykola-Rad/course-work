using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class CounterpartyRole
{
    public int RoleId { get; set; }

    public string Name { get; set; } = null!;

    public virtual ICollection<Counterparty> CounterpartyNames { get; set; } = new List<Counterparty>();
}
