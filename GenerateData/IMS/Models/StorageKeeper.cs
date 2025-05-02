using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class StorageKeeper
{
    [Key] 
    [StringLength(13)]
    public string PhoneNumber { get; set; } = null!;

    [StringLength(100)]
    public string StorageName { get; set; } = null!;

    [StringLength(50)]
    public string FirstName { get; set; } = null!;

    [StringLength(50)]
    public string LastName { get; set; } = null!;

    [EmailAddress]
    [StringLength(255)]
    public string? Email { get; set; }

    public int? UserId { get; set; }

    public virtual ICollection<Invoice> InvoiceReceiverKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual Storage StorageNameNavigation { get; set; } = null!;

    public virtual User? User { get; set; }
}