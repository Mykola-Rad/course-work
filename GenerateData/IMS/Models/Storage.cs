using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class Storage
{
    [Key]
    [Required(ErrorMessage = "Storage name is required.")]
    [StringLength(100, MinimumLength = 3, ErrorMessage = "Storage name must be at least 3 characters long.")]
    [Display(Name = "Storage Name")]
    public string Name { get; set; } = null!;

    [Required(ErrorMessage = "Street name is required.")]
    [StringLength(100, MinimumLength = 3, ErrorMessage = "Street name must be at least 3 characters long.")]
    [Display(Name = "Street")]
    public string StreetName { get; set; } = null!;

    [Required(ErrorMessage = "House number is required.")]
    [StringLength(10, MinimumLength = 1, ErrorMessage = "House number must be at least 1 character long.")]
    [Display(Name = "House Number")]
    public string HouseNumber { get; set; } = null!;

    [Required(ErrorMessage = "City name is required.")]
    [StringLength(50, MinimumLength = 2, ErrorMessage = "City name must be at least 2 characters long.")]
    [Display(Name = "City")]
    public string City { get; set; } = null!;

    [Required(ErrorMessage = "Region name is required.")]
    [StringLength(50, MinimumLength = 2, ErrorMessage = "Region name must be at least 2 characters long.")]
    [Display(Name = "Region/Province")]
    public string Region { get; set; } = null!;

    [Required(ErrorMessage = "Postal code is required.")]
    [StringLength(10, MinimumLength = 5, ErrorMessage = "Postal code must be at least 5 characters long.")]
    [DataType(DataType.PostalCode)]
    [Display(Name = "Postal Code")]
    public string PostalCode { get; set; } = null!;

    public virtual ICollection<Invoice> InvoiceReceiverStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<StorageKeeper> StorageKeepers { get; set; } = new List<StorageKeeper>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();
}