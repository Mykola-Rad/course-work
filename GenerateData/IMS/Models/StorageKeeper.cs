using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.ComponentModel.DataAnnotations;

namespace IMS.Models;

public partial class StorageKeeper
{
    [Key]
    [Required(ErrorMessage = "Номер телефону є обов'язковим.")]
    [StringLength(13, MinimumLength = 10, ErrorMessage = "Довжина номера телефону (з '+') має бути від 10 до 13 символів.")]
    [RegularExpression(@"^\+\d+$", ErrorMessage = "Номер телефону має починатися зі знаку '+' і містити тільки цифри.")]
    [Display(Name = "Номер телефону")]
    public string PhoneNumber { get; set; } = null!;

    [Required(ErrorMessage = "Необхідно призначити склад.")]
    [StringLength(100)]
    [Display(Name = "Призначений склад")]
    public string StorageName { get; set; } = null!;

    [Required(ErrorMessage = "Ім'я є обов'язковим.")]
    [StringLength(50)]
    [Display(Name = "Ім'я")]
    public string FirstName { get; set; } = null!;

    [Required(ErrorMessage = "Прізвище є обов'язковим.")]
    [StringLength(50)]
    [Display(Name = "Прізвище")]
    public string LastName { get; set; } = null!;

    [EmailAddress(ErrorMessage = "Неправильний формат Email.")]
    [StringLength(255)]
    [Display(Name = "Email")]
    public string? Email { get; set; }

    public int? UserId { get; set; }

    public virtual ICollection<Invoice> InvoiceReceiverKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    public virtual ICollection<Invoice> InvoiceSenderKeeperPhoneNavigations { get; set; } = new List<Invoice>();

    [ForeignKey("StorageName")]
    public virtual Storage StorageNameNavigation { get; set; } = null!;

    [ForeignKey("UserId")]
    public virtual User? User { get; set; }
}