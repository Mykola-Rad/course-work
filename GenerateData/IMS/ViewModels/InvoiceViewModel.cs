using IMS.Models; 
using Microsoft.AspNetCore.Mvc.Rendering; 
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace IMS.ViewModels
{
    public class InvoiceViewModel : IValidatableObject 
    {
        public int InvoiceId { get; set; } 

        [Required(ErrorMessage = "Вкажіть дату.")]
        [DataType(DataType.Date)]
        [Display(Name = "Дата документа")]
        public DateOnly Date { get; set; } = DateOnly.FromDateTime(DateTime.Today);

        [Required(ErrorMessage = "Оберіть тип накладної.")]
        [Display(Name = "Тип накладної")]
        public InvoiceType Type { get; set; }

        [Display(Name = "Статус")]
        public InvoiceStatus Status { get; set; } = InvoiceStatus.draft;

        [Display(Name = "Контрагент")]
        public string? CounterpartyName { get; set; }

        [Display(Name = "Склад-Відправник")]
        public string? SenderStorageName { get; set; }

        [Display(Name = "Склад-Одержувач")]
        public string? ReceiverStorageName { get; set; }

        [Display(Name = "Комірник-Відправник")]
        public string? SenderKeeperPhone { get; set; }

        [Display(Name = "Комірник-Одержувач")]
        public string? ReceiverKeeperPhone { get; set; }

        public List<InvoiceListEntryViewModel> ListEntries { get; set; } = new List<InvoiceListEntryViewModel>();

        public SelectList? AvailableTypes { get; set; }
        public SelectList? AvailableCounterparties { get; set; }
        public SelectList? AvailableStorages { get; set; }
        public SelectList? AvailableKeepers { get; set; }
        public SelectList? AvailableProducts { get; set; }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            bool needsCounterparty = (Type == InvoiceType.supply || Type == InvoiceType.release);
            bool needsSenderStorage = (Type == InvoiceType.release || Type == InvoiceType.transfer);
            bool needsReceiverStorage = (Type == InvoiceType.supply || Type == InvoiceType.transfer);
            bool needsSenderKeeper = (Type == InvoiceType.release || Type == InvoiceType.transfer);
            bool needsReceiverKeeper = (Type == InvoiceType.supply || Type == InvoiceType.transfer);

            if (needsCounterparty && string.IsNullOrEmpty(CounterpartyName))
            {
                yield return new ValidationResult("Контрагент є обов'язковим для цього типу накладної.", new[] { nameof(CounterpartyName) });
            }
            if (needsSenderStorage && string.IsNullOrEmpty(SenderStorageName))
            {
                yield return new ValidationResult("Склад-Відправник є обов'язковим для цього типу накладної.", new[] { nameof(SenderStorageName) });
            }
            if (needsReceiverStorage && string.IsNullOrEmpty(ReceiverStorageName))
            {
                yield return new ValidationResult("Склад-Одержувач є обов'язковим для цього типу накладної.", new[] { nameof(ReceiverStorageName) });
            }
            if (Type == InvoiceType.transfer && SenderStorageName == ReceiverStorageName && !string.IsNullOrEmpty(SenderStorageName))
            {
                yield return new ValidationResult("Склад-Відправник та Склад-Одержувач не можуть бути однаковими для переміщення.", new[] { nameof(ReceiverStorageName) });
            }

            if (needsSenderKeeper && string.IsNullOrEmpty(SenderKeeperPhone))
            {
                yield return new ValidationResult("Комірник-Відправник є обов'язковим для цього типу накладної.", new[] { nameof(SenderKeeperPhone) });
            }
            if (needsReceiverKeeper && string.IsNullOrEmpty(ReceiverKeeperPhone))
            {
                yield return new ValidationResult("Комірник-Одержувач є обов'язковим для цього типу накладної.", new[] { nameof(ReceiverKeeperPhone) });
            }

            if (ListEntries == null || !ListEntries.Any(le => !le.IsMarkedForDeletion)) 
            {
                yield return new ValidationResult("Накладна має містити хоча б одну позицію товару.", new[] { nameof(ListEntries) });
            }
            else
            {
                if (Type == InvoiceType.supply || Type == InvoiceType.release)
                {
                    foreach (var entry in ListEntries.Where(le => !le.IsMarkedForDeletion))
                    {
                        if (entry.Price <= 0)
                        {
                            yield return new ValidationResult($"Ціна для товару '{entry.ProductName}' має бути більше нуля.", new[] { nameof(ListEntries) });
                        }
                    }
                }
            }
        }
    }
}