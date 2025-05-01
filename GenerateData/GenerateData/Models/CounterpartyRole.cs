namespace GenerateData.Models;

public partial class CounterpartyRole
{
    public int RoleId { get; set; }

    public string Name { get; set; } = null!;

    public virtual ICollection<Counterparty> CounterpartyNames { get; set; } = new List<Counterparty>();
}
