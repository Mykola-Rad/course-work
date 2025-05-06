using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class InvoiceListEntryViewModel
    {
        [Required(ErrorMessage = "Оберіть товар.")]
        [Display(Name = "Товар")]
        public string ProductName { get; set; } = null!;

        [Display(Name = "Од. вим.")]
        public string? UnitName { get; set; }

        [Required(ErrorMessage = "Вкажіть кількість.")]
        [Range(0.01, 99999999.99, ErrorMessage = "Кількість має бути більше нуля.")] 
        [Display(Name = "Кількість")]
        public decimal Count { get; set; }

        [Range(0, 99999999.99, ErrorMessage = "Ціна має бути невід'ємною.")]
        [Display(Name = "Ціна за од.")]
        public decimal Price { get; set; } = 0;

        [Display(Name = "Сума")]
        [DisplayFormat(DataFormatString = "{0:N2}")]
        public decimal LineTotal => Count * Price; 

        public bool IsMarkedForDeletion { get; set; } = false;
        public int TempId { get; set; }
    }
}