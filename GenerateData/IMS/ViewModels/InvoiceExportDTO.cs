namespace IMS.ViewModels
{
    public class InvoiceExportDto
    {
        public int InvoiceId { get; set; }
        public DateOnly Date { get; set; }
        public string Type { get; set; } 
        public string Status { get; set; }
        public string? CounterpartyName { get; set; }
        public string? SenderStorageName { get; set; }
        public string? ReceiverStorageName { get; set; }
        public string? SenderKeeperPhone { get; set; } 
        public string? ReceiverKeeperPhone { get; set; } 
        public List<ListEntryExportDto> Items { get; set; } = new();
        public decimal TotalAmount { get; set; }
    }
}
