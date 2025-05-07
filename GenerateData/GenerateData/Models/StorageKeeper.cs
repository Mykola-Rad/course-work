namespace GenerateData.Models;

public partial class StorageKeeper
{
    public string PhoneNumber { get; set; } = null!;

    public string StorageName { get; set; } = null!;

    public string FirstName { get; set; } = null!;

    public string LastName { get; set; } = null!;

    public string? Email { get; set; }

    public int? UserId { get; set; }

    public virtual ICollection<Invoice> InvoiceReceiverKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual Storage StorageNameNavigation { get; set; } = null!;

    public virtual User? User { get; set; }
}
