namespace GenerateData.Generators
{
    public interface IEntityGenerator<TEntity> where TEntity : class
    {
       List<TEntity> Generate(int count, GenerationContext context);
    }
}
