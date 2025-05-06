namespace GenerateData.Models;

public partial class ListEntry
{
    public int InvoiceId { get; set; }

    public string ProductName { get; set; } = null!;

    public decimal Count { get; set; }

    public decimal Price { get; set; }

    public virtual Invoice Invoice { get; set; } = null!;

    public virtual Product ProductNameNavigation { get; set; } = null!;
}
