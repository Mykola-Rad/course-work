namespace GenerateData.Generators
{
    public class GenerationContext
    {
        public List<string> AvailableProductNames { get; set; } = new List<string>();
        public List<int> AvailableInvoiceIds { get; set; } = new List<int>();
        public Dictionary<string, List<string>> AvailableStorageKeepers { get; set; } = new Dictionary<string, List<string>>();
        public  List<string> AvailableUsernames { get; set; } = new List<string>();
        public List<string> AvailableKeeperUsernames { get; set; } = new List<string>();
        public List<string> AvailableCounterpartyNames { get; set; } = new List<string>();
        public List<string> AvailableUnitCodes { get; set; } = new List<string>();
        public List<string> AvailableRoles { get; set; } = new List<string>();
        public List<(string storageName, string productName)> AvailableStorageProducts { get; set; } = new List<(string, string)>();
    }
}
