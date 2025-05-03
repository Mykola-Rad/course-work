using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class Storage
{
    [Key] 
    [Required(ErrorMessage = "Назва складу є обов'язковою.")]
    [StringLength(100)]
    [Display(Name = "Назва складу")]
    public string Name { get; set; } = null!;

    [Required(ErrorMessage = "Назва вулиці є обов'язковою.")]
    [StringLength(100)]
    [Display(Name = "Вулиця")]
    public string StreetName { get; set; } = null!;

    [Required(ErrorMessage = "Номер будинку є обов'язковим.")]
    [StringLength(10)]
    [Display(Name = "Номер будинку")]
    public string HouseNumber { get; set; } = null!;

    [Required(ErrorMessage = "Назва міста є обов'язковою.")]
    [StringLength(50)]
    [Display(Name = "Місто")]
    public string City { get; set; } = null!;

    [Required(ErrorMessage = "Назва області є обов'язковою.")]
    [StringLength(50)]
    [Display(Name = "Область/Регіон")]
    public string Region { get; set; } = null!;

    [Required(ErrorMessage = "Поштовий індекс є обов'язковим.")]
    [StringLength(10)] 
    [DataType(DataType.PostalCode)]
    [Display(Name = "Поштовий індекс")]
    public string PostalCode { get; set; } = null!;

    public virtual ICollection<Invoice> InvoiceReceiverStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderStorageNameNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<StorageKeeper> StorageKeepers { get; set; } = new List<StorageKeeper>();

    public virtual ICollection<StorageProduct> StorageProducts { get; set; } = new List<StorageProduct>();
}
