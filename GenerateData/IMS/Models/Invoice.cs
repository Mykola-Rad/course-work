using System;
using System.Collections.Generic;

namespace IMS.Models;

public partial class Invoice
{
    public int InvoiceId { get; set; }

    public string? CounterpartyName { get; set; }

    public string? SenderKeeperPhone { get; set; }

    public string? ReceiverKeeperPhone { get; set; }

    public string? SenderStorageName { get; set; }

    public string? ReceiverStorageName { get; set; }

    public string Type { get; set; } = null!;

    public DateOnly Date { get; set; }

    public virtual Counterparty? CounterpartyNameNavigation { get; set; }

    public virtual ICollection<ListEntry> ListEntries { get; set; } = new List<ListEntry>();

    public virtual StorageKeeper? ReceiverKeeperPhoneNavigation { get; set; }

    public virtual Storage? ReceiverStorageNameNavigation { get; set; }

    public virtual StorageKeeper? SenderKeeperPhoneNavigation { get; set; }

    public virtual Storage? SenderStorageNameNavigation { get; set; }
}
