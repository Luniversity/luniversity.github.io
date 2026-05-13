using UnityEngine;

public class StarSpawner : MonoBehaviour
{
    public GameObject starPrefab;
    public int numberOfStars = 200;

    public float width = 20f;
    public float height = 10f;

    public float Scale = 0.2f;


    void Start()
    {
        for (int i = 0; i < numberOfStars; i++)
        {
            Vector3 localPosition = new Vector3(
                Random.Range(-width / 2f, width / 2f),
                Random.Range(-height / 2f, height / 2f),
                0f
            );

            Vector3 worldPosition = transform.TransformPoint(localPosition);

            GameObject star = Instantiate(
                starPrefab,
                worldPosition,
                transform.rotation
            );

            star.transform.localScale = Vector3.one * Scale;

            star.transform.SetParent(transform);
        }
    }
}